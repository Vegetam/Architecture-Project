# Runbook — Resilience Game Day Playbook

**Purpose**: Step-by-step guide for running a structured resilience game day against the Vegetam staging environment.

**Duration**: ~45 minutes  
**Prerequisite**: Staging is stable and the weekly canary analysis is green.

---

## Pre-Game Day Checklist

Before running experiments, confirm:

- [ ] No active incidents in production (`kubectl get alerts -n observability`)
- [ ] All staging pods are Running: `kubectl get pods -n microservices-staging`
- [ ] No Argo Rollouts in progress: `kubectl argo rollouts list rollouts -n microservices-staging`
- [ ] Prometheus is accessible: `curl -sf http://localhost:9090/-/healthy`
- [ ] You have a Slack/incident bridge open so you can communicate if something goes wrong
- [ ] The on-call engineer is aware a game day is starting

---

## Running the Full Game Day

```bash
# Option 1: LitmusChaos orchestrated workflow (recommended — scores automatically)
kubectl apply -f litmus/workflows/resilience-gameday.yaml

# Watch the workflow progress
kubectl get chaosengine resilience-gameday -n litmus -w

# Option 2: Run individual experiments with automatic scoring
./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml
./scripts/run-experiment.sh chaos-mesh/experiments/pod/pod-kill-order-service.yaml
./scripts/run-experiment.sh chaos-mesh/experiments/stress/cpu-stress-payment.yaml
./scripts/run-experiment.sh chaos-mesh/experiments/pod/pod-failure-saga.yaml
./scripts/run-experiment.sh chaos-mesh/experiments/network/packet-loss-kafka.yaml
```

---

## Experiment Sequence

Run experiments in this order — ordered by blast radius (smallest first):

| # | Experiment | Risk | Expected behaviour |
|---|---|---|---|
| 1 | `latency-order-service` | LOW | p99 degrades, Alertmanager fires, recovers within 60s |
| 2 | `pod-kill-order-service` | LOW | One pod restarts, k8s reschedules, success rate stays > 90% |
| 3 | `cpu-stress-payment` | MEDIUM | Payment-service CPU saturated, retries increase, no errors |
| 4 | `memory-stress-order` | MEDIUM | OOM risk — watch for OOMKill events in Loki |
| 5 | `pod-failure-saga` | HIGH | Saga orchestrator crash-loops, compensation logic tested |
| 6 | `packet-loss-kafka` | MEDIUM | Message delay increases, no duplicate processing |
| 7 | `disk-latency-postgres` | MEDIUM | DB slow queries surface in Loki, circuit breaker activates |

Allow **2 minutes of stabilisation** between each experiment.

---

## Watching Dashboards

Open these Grafana dashboards during the game day:

1. **Chaos Resilience** (`grafana/dashboards/chaos-resilience.json`) — experiment verdicts + score
2. **Services Overview** (from observability-platform-turnkey) — error rates + latency
3. **Saga State Machine** (from observability-platform-turnkey) — compensation counts

---

## Interpreting Results

**PASS criteria** (all must be true):
- Resilience Score ≥ 80
- No experiment left the system in a non-steady state after the 60s recovery window
- No unintended production impact

**If an experiment FAILS:**
See [experiment-failed.md](./experiment-failed.md).

**If production is impacted during a game day:**
See [production-incident-during-chaos.md](./production-incident-during-chaos.md).

---

## Post-Game Day

```bash
# Confirm no orphaned chaos resources remain
kubectl get networkchaos,podchaos,stresschaos,iochaos -A

# If any remain from a manual abort:
kubectl delete networkchaos,podchaos,stresschaos,iochaos --all -n chaos-testing

# Export resilience score
kubectl get chaosresult -n litmus -o yaml | \
  python3 -c "import sys,yaml; [print(r['status']['experimentStatus']['verdict']) for r in yaml.safe_load(sys.stdin)['items']]"
```

Record the score in the team's resilience tracking sheet.
