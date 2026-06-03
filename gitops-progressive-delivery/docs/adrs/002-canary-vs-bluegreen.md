# ADR 002 — Canary for order-service, Blue/Green for payment-service

**Status:** Accepted
**Date:** 2026-02

## Context

We needed a progressive delivery strategy for two types of services:
- **Stateless, idempotent** (order-service, saga-orchestrator): requests can be retried
- **Financially sensitive** (payment-service): duplicate processing must be prevented

## Decision

- **order-service / saga-orchestrator:** Canary (gradual traffic shift)
- **payment-service:** Blue/Green (hard cutover with manual approval)

## Reasoning

### Canary for stateless services

- 5% → 25% → 50% → 100% shift over ~15 minutes
- Prometheus analysis runs between each step
- Error spike automatically rolls back — no human intervention
- Real user traffic validates the new version at each step
- Zero downtime: stable pods serve 95% while canary receives 5%

### Blue/Green for payment-service

- Green (new version) receives zero traffic until promotion
- `prePromotionAnalysis` runs synthetic health checks against Green
- Human must explicitly promote (`./scripts/promote.sh rollout payment-service`)
- Blue stays alive for 5 minutes after promotion for instant rollback
- Prevents two payment service versions from processing the same transaction

## Consequences

- canary requires two Services per rollout (stable + canary) — more K8s objects
- blue/green doubles resource usage during deployment (Blue + Green both running)
- Manual promotion of payment-service means slightly slower release cycle
- Both strategies feed real signal back into the observability platform (traces + metrics)
