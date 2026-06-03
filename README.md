# Architecture Project

A **reference platform** demonstrating production patterns across GitOps delivery, observability, and chaos engineering on Kubernetes. This is the **direct continuation** of [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka), [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture), and [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) — those repos define the application layer and infrastructure; this repo adds the platform layer on top.

Each project implements real patterns with runnable code, tested services, and operational documentation. Where full application code is out of scope, **mock services mirror the real service contracts** — same endpoints, same Prometheus metric names — so the platform behaviour is testable end-to-end without the full application stack.

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
- Stub services with non-root Dockerfiles, HEALTHCHECK, graceful shutdown, and smoke tests
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
- Mock services with non-root Dockerfiles, HEALTHCHECK, and `node:test` smoke tests
- Grafana dashboard for chaos metrics and score trend tracking
- Docker Compose local stack — `docker compose up` gives you Prometheus + Grafana + target services
- kind-based local setup for real chaos injection without a cloud cluster
- 3 ADRs, 3 runbooks (game day playbook, experiment failed, production incident)

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
│  Real implementations: microservices-ddd-kafka + Saga-pattern       │
│  Mock stubs (same contract): gitops/services/ + chaos/mock-services/│
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

### Mock services vs real services

Two sets of service stubs exist in this repo — this is intentional, not drift:

| Location | Purpose | Contract |
|---|---|---|
| `gitops-progressive-delivery/services/` | Deployment stubs for the GitOps pipeline CI | Same health endpoints as real services |
| `chaos-engineering-platform/docker/mock-services/` | Local targets for chaos injection and steady-state testing | Same Prometheus metric names as real services |

Neither replaces the real implementations in [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka). They exist to make the platform testable without the full application stack.

---

## Repository Structure

```
Architecture-Project/
├── CODEOWNERS
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

The root workflows use **path-based change detection** — only the jobs for the changed project run on each push.

| Trigger | Jobs that run |
|---|---|
| Push to `observability-platform-turnkey/**` | `[OBS]` jobs only |
| Push to `gitops-progressive-delivery/**` | `[GITOPS]` jobs only |
| Push to `chaos-engineering-platform/**` | `[CHAOS]` jobs only |
| `workflow_dispatch` | All jobs |

---

## Quick Start

```bash
# Chaos platform — Prometheus + Grafana + mock services (no Kubernetes needed)
cd chaos-engineering-platform
docker compose -f docker/docker-compose.yml up -d
# open http://localhost:3030  (Grafana — admin/admin)
# open http://localhost:9090  (Prometheus)
```

For full Kubernetes deployment see the individual project READMEs.

---

## Related Repositories

| Repo | Description |
|---|---|
| [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka) | Real service implementations (DDD + Kafka + Saga) — this repo builds on top |
| [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture) | Saga orchestration pattern — services deployed via gitops-progressive-delivery |
| [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) | AWS / Azure / GCP infrastructure (EKS, AKS, GKE) — clusters used by all projects |
| [zero-trust-platform](https://github.com/Vegetam/zero-trust-platform) | Istio mTLS, Vault, Kyverno policies |
| [internal-developer-platform](https://github.com/Vegetam/internal-developer-platform) | Backstage IDP with ArgoCD and Grafana plugins |
