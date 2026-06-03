# Chaos Engineering Platform

Resilience testing for the Vegetam microservices platform. Validates that the system recovers gracefully from network failures, pod crashes, CPU spikes, memory pressure, and disk I/O degradation — **before they happen in production**.

Powered by **Chaos Mesh** (fault injection) + **LitmusChaos** (workflow orchestration + resilience scoring), integrated with the same **Prometheus** that drives Argo Rollouts canary analysis.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Chaos Engineering Platform                                     │
│                                                                 │
│  Chaos Mesh (fault injection)                                   │
│  ├── NetworkChaos: latency, packet-loss, partition             │
│  ├── PodChaos:     pod-kill, pod-failure                       │
│  ├── StressChaos:  cpu-hog, memory-hog                         │
│  └── IOChaos:      disk-latency on PostgreSQL                  │
│                                                                 │
│  LitmusChaos (orchestration)                                    │
│  └── ChaosWorkflow: resilience-gameday                         │
│      (sequences all experiments + calculates Resilience Score)  │
└─────────┬────────────────────────────────────┬──────────────────┘
          │ injects faults into                │ queries
          ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────┐
│  microservices      │              │  observability-      │
│  (staging namespace)│              │  platform-turnkey    │
│                     │              │                      │
│  order-service      │              │  Prometheus          │
│  payment-service    │              │  ← steady-state      │
│  saga-orchestrator  │              │    probes            │
└─────────────────────┘              │  Grafana             │
                                     │  ← chaos dashboards  │
          ▲                          │  Loki                │
          │ canary analysis          │  ← chaos event logs  │
          │ uses same Prometheus     └─────────────────────┘
          │
┌─────────────────────┐
│  gitops-progressive-│
│  delivery           │
│  Argo Rollouts      │
│  (p99 < 500ms,      │
│   success > 95%)    │
└─────────────────────┘
```

---

## Repository Map

```
chaos-engineering-platform/
│
├── chaos-mesh/
│   ├── install/
│   │   └── chaos-mesh-values.yaml             # Helm values (dashboard, RBAC, metrics)
│   └── experiments/
│       ├── network/
│       │   ├── latency-order-service.yaml      # 200ms latency + 50ms jitter
│       │   ├── partition-payment-service.yaml  # Full network cut (staging only)
│       │   └── packet-loss-kafka.yaml          # 20% packet loss to Kafka
│       ├── pod/
│       │   ├── pod-kill-order-service.yaml     # Kill one pod every 2min
│       │   └── pod-failure-saga.yaml           # Crash loop saga-orchestrator
│       ├── stress/
│       │   ├── cpu-stress-payment.yaml         # 80% CPU for 5min
│       │   └── memory-stress-order.yaml        # 90% memory → OOM test
│       ├── io/
│       │   └── disk-latency-postgres.yaml      # 100ms disk I/O on PostgreSQL
│       ├── time/
│       │   └── time-skew-payment.yaml          # +30s clock skew → JWT/saga ordering
│       └── http/
│           └── http-error-order.yaml           # 503 on 20% of POST /orders
│
├── litmus/
│   ├── install/
│   │   └── litmus-values.yaml                 # LitmusChaos Helm values
│   └── workflows/
│       └── resilience-gameday.yaml            # Full game day ChaosEngine (score 0-100)
│
├── analysis/
│   └── steady-state.yaml                      # Hypothesis: 6 probes across all services
│
├── grafana/dashboards/
│   └── chaos-resilience.json                  # Resilience score + service health panels
│
├── scripts/
│   ├── bootstrap.sh                            # Install Chaos Mesh + LitmusChaos
│   └── run-experiment.sh                       # Safe runner with pre/post steady-state check
│
├── .github/workflows/
│   ├── validate.yml                            # Manifest validation + namespace safety check
│   └── security.yml                            # Secret scan, RBAC audit, duration safety
│
└── docs/
    ├── adrs/
    │   ├── 001-chaos-mesh-vs-litmus.md         # Why both tools
    │   ├── 002-steady-state-hypothesis.md      # Probe design and recovery window
    │   └── 003-gameday-cadence-and-scoring.md  # Release gate + weekly baseline policy
    └── runbooks/
        ├── gameday-playbook.md                 # Step-by-step game day execution
        ├── experiment-failed.md                # Recovery when an experiment fails
        └── production-incident-during-chaos.md # Stop chaos, determine cause, resume
```

---

## How It Connects to the Platform

| Repo | Chaos Integration |
|---|---|
| [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka) | Target: order-service, payment-service, saga-orchestrator pods |
| [observability-platform-turnkey-fixed](https://github.com/Vegetam/observability-platform-turnkey-fixed) | Prometheus steady-state probes; Grafana chaos dashboards; Loki for chaos event logs |
| [gitops-progressive-delivery](https://github.com/Vegetam/gitops-progressive-delivery) | Argo Rollouts analysis uses same Prometheus — chaos validates that thresholds are correctly calibrated |
| [zero-trust-platform](https://github.com/Vegetam/zero-trust-platform) | Chaos tests that Istio circuit breaker + AuthorizationPolicy work correctly under partial failures |

---

## Quick Start

```bash
git clone https://github.com/Vegetam/chaos-engineering-platform
cd chaos-engineering-platform

# Install Chaos Mesh + LitmusChaos
make bootstrap

# List all available experiments with risk levels
make list-experiments

# Run a single low-risk experiment (with automatic steady-state checks)
./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml

# Run the full resilience game day (scores 0-100)
make gameday

# Emergency: stop all running experiments immediately
make clean-experiments
```

See [docs/runbooks/gameday-playbook.md](docs/runbooks/gameday-playbook.md) for the full structured game day guide.

---

## Experiment Risk Levels

| Level | Target | When to Run |
|---|---|---|
| **low** | Staging | Any time, automated in CI weekly |
| **medium** | Staging | Before major releases |
| **high** | Staging only | Manually, with engineer present |

The CI enforces that `risk-level: high` experiments cannot target the `microservices` (production) namespace. See [validate.yml](.github/workflows/validate.yml).

---

## Resilience Score

After each game day, LitmusChaos calculates a **Resilience Score** (0-100) based on how many Prometheus probes passed during chaos. This score is:
- Emitted as a Prometheus metric (`litmuschaos_experiment_verdict`)
- Visualised in Grafana (add `litmuschaos_experiment_verdict` to your platform dashboard)
- Tracked over time to show resilience improvements across releases

**Target**: Resilience Score ≥ 80 before any production release.

---

## Grafana Dashboard

Import [grafana/dashboards/chaos-resilience.json](grafana/dashboards/chaos-resilience.json) into your Grafana instance for:
- **Resilience Score** (0–100) with green/amber/red thresholds (≥80 = production-ready)
- **Experiment pass/fail verdict** timeline
- **Service success rates and p99 latency** during fault injection
- **Score trend** across weekly game days

---

## ADRs

- [ADR 001 — Chaos Mesh vs LitmusChaos vs Gremlin](docs/adrs/001-chaos-mesh-vs-litmus.md)
- [ADR 002 — Steady State Hypothesis Design](docs/adrs/002-steady-state-hypothesis-design.md)
- [ADR 003 — Game Day Cadence and Resilience Scoring](docs/adrs/003-gameday-cadence-and-scoring.md)

## Runbooks

- [Game Day Playbook](docs/runbooks/gameday-playbook.md) — step-by-step execution guide
- [Experiment Failed](docs/runbooks/experiment-failed.md) — recovery procedures
- [Production Incident During Chaos](docs/runbooks/production-incident-during-chaos.md) — stop chaos, triage, resume
