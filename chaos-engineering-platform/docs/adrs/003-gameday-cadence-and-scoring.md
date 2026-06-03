# ADR 003 — Game Day Cadence and Resilience Scoring

**Status**: Accepted
**Date**: 2024-03-01

---

## Context

Running chaos experiments ad-hoc has diminishing value — you lose the ability to track resilience *trends* across releases. We need a policy for:
1. How often game days run and who triggers them
2. What score is required before a production release
3. How to track score changes over time

---

## Options

### Option A: Fully automated game days in CI
Game days run on every merge to main. Fast feedback but high noise; staging is not always stable enough for a full game day immediately post-merge.

### Option B: Release-gated game days (chosen)
A game day is a mandatory gate before production promotion. A weekly scheduled game day also runs independently of releases for trend data.

### Option C: Manual game days only
Too slow; resilience regressions accumulate between runs.

---

## Decision

**Two-tier cadence:**

| Tier | Trigger | Scope | Blocking? |
|---|---|---|---|
| **Release gate** | Before staging → production promotion (Argo Rollouts) | Full resilience-gameday workflow | Yes — score < 80 blocks promotion |
| **Weekly baseline** | Scheduled (Sunday 02:00 UTC, low-traffic window) | Full game day | No — alerts on regression ≥ 10 points vs previous week |

**Resilience Score calculation (LitmusChaos):**

```
score = (probes_passed / total_probes) × 100
```

Each experiment in the `resilience-gameday` workflow contributes equally (weight 20). A probe failure during chaos does *not* reduce the score if the system recovers — only unrecovered probes count against the score.

**Thresholds:**

| Score | Meaning | Action |
|---|---|---|
| ≥ 80 | Production-ready | Promote |
| 60–79 | Degraded resilience | Alert + review before promoting |
| < 60 | Critical resilience regression | Block promotion, create P1 ticket |

---

## Consequences

- The weekly game day result is stored as a Prometheus metric (`litmuschaos_experiment_verdict`) with a `run_type` label (`release_gate` or `weekly_baseline`)
- Grafana tracks the score trendline across weeks
- The release gate is enforced by `scripts/run-experiment.sh` returning non-zero on score < 80
- Game day results are announced in #platform-reliability Slack channel via Alertmanager webhook
