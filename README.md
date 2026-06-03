# Architecture Project

A monorepo containing three production-grade platform engineering projects built on Kubernetes. This is the **direct continuation** of [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka), [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture), and [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) — those repos define the application layer and infrastructure; this repo adds the platform layer on top: GitOps delivery, full observability, and chaos engineering.

Each project is independently deployable and integrates with the others to form a complete platform engineering stack.

[![CI](https://github.com/Vegetam/Architecture-Project/actions/workflows/ci.yml/badge.svg)](https://github.com/Vegetam/Architecture-Project/actions/workflows/ci.yml)
[![Validate](https://github.com/Vegetam/Architecture-Project/actions/workflows/validate.yml/badge.svg)](https://github.com/Vegetam/Architecture-Project/actions/workflows/validate.yml)
[![Security](https://github.com/Vegetam/Architecture-Project/actions/workflows/security.yml/badge.svg)](https://github.com/Vegetam/Architecture-Project/actions/workflows/security.yml)

---

## Projects

### 1. GitOps Progressive Delivery
**Directory**: `gitops-progressive-delivery/`

Pull-based GitOps with automated canary and blue/green deployments. Powered by ArgoCD and Argo Rollouts, with deployment decisions driven by live Prometheus metrics.

**Key features:**
- ArgoCD App of Apps pattern — single source of truth for all deployments
- Canary deployments for order-service and saga-orchestrator (5% → 25% → 50% → 100%)
- Blue/Green deployment for payment-service (financial safety — no dual-version processing)
- Automated promotion and rollback based on Prometheus success rate and p99 latency
- Kustomize overlays for dev / staging / production environments
- Reusable Helm chart supporting canary, blue/green, or plain Deployment strategy
- GitHub Actions CI: build → Trivy scan → push to GHCR → update image tag in git

**Stack**: ArgoCD, Argo Rollouts, Kustomize, Helm, Prometheus, GitHub Container Registry

---

### 2. Observability Platform Turnkey
**Directory**: `observability-platform-turnkey/`

Production-ready observability stack deployable to EKS, GKE, or AKS with a single command. Full LGTM stack with OpenTelemetry as the collection backbone.

**Key features:**
- OpenTelemetry Collector as the central hub — metrics, traces, and logs in one pipeline
- Grafana Tempo for distributed tracing with S3/MinIO long-term storage
- Loki for structured log aggregation with S3/MinIO backend
- Prometheus + kube-prometheus-stack for metrics
- Kong API Gateway with OTel tracing and JWT auth
- 6 operational runbooks (DR, backup/restore, capacity, incidents, upgrade, retention)
- Docker Compose for local development — full stack in one command
- Helm values pre-configured for AWS, Azure, and GCP

**Stack**: OpenTelemetry, Grafana, Tempo, Loki, Prometheus, Alertmanager, Kong, MinIO

---

### 3. Chaos Engineering Platform
**Directory**: `chaos-engineering-platform/`

Resilience testing for the Vegetam microservices platform. Validates that the system recovers gracefully from network failures, pod crashes, CPU spikes, memory pressure, disk I/O degradation, clock skew, and HTTP errors — before they happen in production.

**Key features:**
- 10 Chaos Mesh experiments across 6 fault categories (network, pod, stress, IO, time, HTTP)
- LitmusChaos game day workflow with automated Resilience Score (0–100)
- Steady-state hypothesis with 6 Prometheus probes — aborts if system already degraded
- Safe experiment runner with pre/post steady-state verification and resilience report
- Grafana dashboard for chaos metrics and score trend tracking
- Docker Compose local stack with mock services for testing without Kubernetes
- kind-based local setup for real chaos injection
- 3 ADRs, 3 runbooks (game day playbook, experiment failed, production incident)
- CI: manifest validation, namespace safety check, shell script lint, security scan

**Stack**: Chaos Mesh, LitmusChaos, Prometheus, Grafana, kind, Docker

---

## How the Projects Connect

```
┌─────────────────────────────────────────────────────────────────────┐
│  gitops-progressive-delivery                                        │
│  ArgoCD + Argo Rollouts                                             │
│  Deploys microservices to staging and production                    │
│  Canary analysis uses Prometheus from observability-platform        │
└────────────────────────┬────────────────────────────────────────────┘
                         │ deploys to
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  microservices (order-service, payment-service, saga-orchestrator)  │
│  Target of both GitOps deployments and chaos experiments            │
│  Defined in: microservices-ddd-kafka + Saga-pattern-architecture    │
└──────────┬──────────────────────────────────────┬───────────────────┘
           │ emits OTel traces/metrics             │ chaos injected by
           ▼                                       ▼
┌────────────────────────────┐     ┌───────────────────────────────────┐
│  observability-platform    │     │  chaos-engineering-platform       │
│  Prometheus, Grafana,      │◄────│  Chaos Mesh + LitmusChaos         │
│  Tempo, Loki               │     │  Steady-state checks query        │
│  Drives canary analysis    │     │  the same Prometheus              │
└────────────────────────────┘     └───────────────────────────────────┘
                         ▲
                         │ infrastructure provisioned by
┌────────────────────────┴────────────────────────────────────────────┐
│  terraform-multicloud                                               │
│  EKS / AKS / GKE clusters — the deployment targets for everything  │
└─────────────────────────────────────────────────────────────────────┘
```

| Project | Depends On | Provides To |
|---|---|---|
| terraform-multicloud | — | EKS/AKS/GKE clusters for all projects |
| observability-platform-turnkey | — | Prometheus metrics to gitops + chaos |
| gitops-progressive-delivery | observability (Prometheus) | Deployed microservices |
| chaos-engineering-platform | observability (Prometheus) | Resilience scores, failure validation |

---

## Repository Structure

```
Architecture-Project/
├── .github/workflows/
│   ├── ci.yml          # Per-project CI with path-based change detection
│   ├── validate.yml    # YAML, Kustomize, Helm, ArgoCD, PromQL validation
│   └── security.yml    # Trivy filesystem scans (weekly + on push)
│
├── gitops-progressive-delivery/
├── observability-platform-turnkey/
└── chaos-engineering-platform/
```

### CI/CD Pipeline

The root workflows use **path-based change detection** — only the jobs for the changed project run on each push. Unrelated projects are skipped.

| Trigger | Jobs that run |
|---|---|
| Push to `observability-platform-turnkey/**` | `[OBS]` jobs only |
| Push to `gitops-progressive-delivery/**` | `[GITOPS]` jobs only |
| Push to `chaos-engineering-platform/**` | `[CHAOS]` jobs only |
| `workflow_dispatch` | All jobs |

---

## Quick Start

Each project has its own `README.md` with full setup instructions. For a local demo without Kubernetes:

```bash
# Observability stack
cd observability-platform-turnkey
docker compose -f docker/docker-compose.yml up -d

# Chaos platform with mock services + Grafana
cd chaos-engineering-platform
docker compose -f docker/docker-compose.yml up -d
# open http://localhost:3030 (Grafana — admin/admin)
```

For full Kubernetes deployment see the individual project READMEs.

---

## Related Repositories

| Repo | Description |
|---|---|
| [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka) | Target microservices (DDD + Kafka + Saga) — this repo builds on top |
| [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture) | Saga orchestration pattern — services deployed via gitops-progressive-delivery |
| [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) | AWS / Azure / GCP infrastructure (EKS, AKS, GKE) — clusters used by all projects |
| [zero-trust-platform](https://github.com/Vegetam/zero-trust-platform) | Istio mTLS, Vault, Kyverno policies |
| [internal-developer-platform](https://github.com/Vegetam/internal-developer-platform) | Backstage IDP with ArgoCD and Grafana plugins |
