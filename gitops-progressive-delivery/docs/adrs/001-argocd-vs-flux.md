# ADR 001 — ArgoCD over Flux

**Status:** Accepted
**Date:** 2026-02

## Context

Both ArgoCD and Flux are CNCF-graduated GitOps controllers. We needed to choose one for the platform.

## Decision

We chose **ArgoCD**.

## Reasons

| Criterion | ArgoCD | Flux |
|---|---|---|
| UI | Full web UI with diff view | CLI-first, no native UI |
| RBAC | AppProject scoping per team/namespace | Coarser RBAC |
| Multi-cluster | Native, multiple cluster targets in one install | Requires one Flux per cluster |
| Rollouts integration | Native health check for `argoproj.io/Rollout` | Requires custom health checks |
| Notification system | Built-in notifications controller | External tool needed |
| Audit trail | Operation history visible in UI and API | Git commit history only |
| Learning curve | Higher (more CRDs) | Lower |

The tight integration between **ArgoCD + Argo Rollouts** (both from the Argoproj project) was the deciding factor. ArgoCD understands Rollout health states natively, and Argo Rollouts can pause/resume based on ArgoCD sync status. Flux would require custom health check wiring.

## Consequences

- All cluster state is declarative in this repo and reconciled by ArgoCD.
- Manual `kubectl apply` in managed namespaces is prohibited (ArgoCD will revert it within seconds).
- AppProject boundaries enforce namespace isolation between teams.
