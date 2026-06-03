# GitOps Progressive Delivery Platform

Pull-based GitOps with automated canary and blue/green deployments for the Vegetam microservices platform. Powered by **ArgoCD** and **Argo Rollouts**, with deployment decisions driven by live **Prometheus metrics** from the [observability-platform](https://github.com/Vegetam/observability-platform-turnkey-fixed).

---

## Platform Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions (CI)                                            │
│  Build → Trivy Scan → Push ghcr.io → Update image tag in git   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ git push (image tag update)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  ArgoCD (GitOps controller)                                     │
│  Watches this repo → reconciles cluster state to match git      │
│                                                                 │
│  App of Apps                                                    │
│  ├── microservices-staging   (auto-sync)                        │
│  ├── microservices-production (manual sync, business hours)     │
│  └── observability-platform  (auto-sync, never prune)           │
└───────────────────────────┬─────────────────────────────────────┘
                            │ applies Kustomize overlays
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Argo Rollouts (progressive delivery controller)                │
│                                                                 │
│  order-service    → Canary  (5%→25%→50%→100%, auto-promote)    │
│  payment-service  → Blue/Green (manual promote, 5 min rollback) │
│  saga-orchestrator→ Canary  (5%→25%→50%→100%, auto-promote)    │
│                                                                 │
│  At each step → AnalysisRun queries Prometheus:                 │
│    ✓ success rate ≥ 95%   → proceed                            │
│    ✗ success rate < 90%   → auto rollback                      │
│    ✓ p99 latency < 500ms  → proceed                            │
└─────────────────────────────────────────────────────────────────┘
                            ▲
                            │ metrics (otel_http_server_duration_*)
┌─────────────────────────────────────────────────────────────────┐
│  observability-platform-turnkey-fixed                           │
│  OTel Collector → Prometheus (spanmetrics)                      │
│  The same Prometheus that feeds Grafana dashboards              │
│  also drives canary promotion / rollback decisions              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Repository Map

```
gitops-progressive-delivery/
├── argocd/
│   ├── install/          # ArgoCD Helm values
│   ├── projects/         # AppProjects (RBAC scoping)
│   ├── apps/             # ArgoCD Applications (App of Apps pattern)
│   └── notifications/    # Slack + PagerDuty notification templates
│
├── argo-rollouts/
│   ├── install/          # Argo Rollouts Helm values
│   ├── rollouts/         # Rollout CRDs (canary + blue/green)
│   └── analysis/         # AnalysisTemplates (Prometheus queries)
│
├── helm-charts/
│   └── microservice/     # Reusable chart for all microservices
│                         # Supports canary, blue/green, or plain Deployment
│
├── environments/
│   ├── base/             # Shared base (analysis templates + helm chart refs)
│   ├── dev/              # Dev overlay (1 replica, minimal resources)
│   ├── staging/          # Staging overlay (auto-sync, uses latest tag)
│   └── production/       # Production overlay (manual sync, pinned SHA)
│
├── scripts/
│   ├── bootstrap.sh      # One-command cluster setup
│   └── promote.sh        # Promote/abort rollouts, sync production
│
└── .github/workflows/
    ├── ci.yml            # Build → Scan → Push → Update staging tag
    └── validate.yml      # Kustomize + Helm + PromQL validation on PR
```

---

## How It Connects to the Vegetam Platform

| Repo | Role | Integration Point |
|---|---|---|
| [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka) | Application code | Services deployed via this repo's Kustomize overlays |
| [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture) | Distributed transactions | `saga-orchestrator` Rollout defined here |
| [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) | Infrastructure | EKS/GKE/AKS clusters are the ArgoCD targets |
| [observability-platform-turnkey-fixed](https://github.com/Vegetam/observability-platform-turnkey-fixed) | Observability | Prometheus metrics drive canary analysis decisions |

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| kubectl | ≥ 1.29 | Cluster interaction |
| helm | ≥ 3.14 | Chart installs |
| argocd CLI | ≥ 2.11 | App management |
| kubectl-argo-rollouts | ≥ 1.7 | Rollout management |
| kustomize | ≥ 5.4 | Overlay building |

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/Vegetam/gitops-progressive-delivery
cd gitops-progressive-delivery

export ARGOCD_HOSTNAME=argocd.your-domain.com
export CLUSTER=your-kubecontext
```

### 2. Bootstrap the cluster

```bash
./scripts/bootstrap.sh
```

This installs cert-manager → ingress-nginx → ArgoCD → Argo Rollouts → applies the App of Apps. From this point, git is the source of truth. Every push to `main` triggers a reconciliation.

### 3. Watch ArgoCD sync everything

```bash
kubectl get applications -n argocd -w
# or open https://${ARGOCD_HOSTNAME} in your browser
```

---

## Deployment Flow

### Staging (fully automated)

```
git push main
  → GitHub Actions builds + scans image
  → Pushes to ghcr.io/vegetam/<service>:<sha>
  → Updates environments/staging/kustomization.yaml
  → ArgoCD detects git change, auto-syncs
  → Argo Rollouts starts canary: 5% traffic to new pods
  → Prometheus analysis runs every minute
  → If analysis passes: 25% → 50% → 100%
  → If analysis fails: automatic rollback to previous version
```

### Production (human-gated)

```
CI passes staging validation
  → GitHub Actions waits for "production" environment approval
  → Platform engineer approves in GitHub UI
  → CI pins production/kustomization.yaml to exact SHA
  → Platform engineer runs: ./scripts/promote.sh production
  → ArgoCD syncs production (manual, business hours only)
  → Argo Rollouts starts canary with identical analysis
  → payment-service: platform engineer manually promotes blue/green
```

### Rollback

```bash
# Abort canary and rollback immediately:
./scripts/promote.sh abort order-service

# Or use the Argo Rollouts dashboard:
kubectl argo rollouts dashboard   # opens at localhost:3100
```

---

## Canary Analysis

The `AnalysisTemplate` resources query the Prometheus from `observability-platform-turnkey-fixed`. The metric names come from the OTel Collector spanmetrics processor — no custom instrumentation needed.

```yaml
# success-rate AnalysisTemplate (simplified)
query: |
  1 - (
    sum(rate(otel_http_server_duration_count{
      service_name="order-service",
      http_status_code=~"5.."
    }[5m]))
    /
    sum(rate(otel_http_server_duration_count{
      service_name="order-service"
    }[5m]))
  )
successCondition: result[0] >= 0.95
failureCondition: result[0] < 0.90
```

If Prometheus is unreachable, the analysis is marked `Inconclusive` (not Failed). After 2 inconclusive results, the rollout pauses for human review rather than auto-rolling back.

---

## Progressive Delivery Strategies

| Service | Strategy | Why |
|---|---|---|
| order-service | Canary | Idempotent, safe to split traffic |
| payment-service | Blue/Green + manual | Financial: no dual-version processing |
| saga-orchestrator | Canary | Stateless coordinator, safe to split |

See [ADR 002](docs/adrs/002-canary-vs-bluegreen.md) for the full rationale.

---

## Alerting Integration

ArgoCD notifications send to the same Slack channels and PagerDuty routing key as `observability-platform-turnkey-fixed`. A failed deployment and a degraded service alert land in the same channel, giving operators full context.

Configure by creating the `argocd-notifications-secret`:

```bash
kubectl create secret generic argocd-notifications-secret \
  --namespace argocd \
  --from-literal=slack-token=${SLACK_TOKEN} \
  --from-literal=pagerduty-routing-key=${PAGERDUTY_ROUTING_KEY}
```

---

## Architecture Decision Records

- [ADR 001 — ArgoCD over Flux](docs/adrs/001-argocd-vs-flux.md)
- [ADR 002 — Canary vs Blue/Green per service type](docs/adrs/002-canary-vs-bluegreen.md)
