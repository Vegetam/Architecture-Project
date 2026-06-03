# ADR 002 — Steady State Hypothesis Design

**Status**: Accepted
**Date**: 2024-02-15

---

## Context

A chaos experiment without a defined steady state is just breaking things. We need a formal hypothesis that:
- Defines "healthy" before chaos starts (abort if already degraded)
- Specifies which signals to watch *during* chaos (tolerance thresholds)
- Determines pass/fail after chaos ends (recovery criteria)

The question is: how many probes, which signals, and how strict should the thresholds be?

---

## Options

### Option A: Single binary probe (all-or-nothing)
One Prometheus query: if error rate > 1%, abort. Simple, but too coarse — a single slow pod would cancel legitimate experiments.

### Option B: Weighted probe set (current approach)
Multiple independent probes across different services and signal types. Each probe is binary pass/fail. The experiment aborts only if the system is already unhealthy *before* chaos starts. During chaos, probes record observations but do not abort (the system is expected to degrade).

### Option C: SLO-window-based hypothesis
Measure multi-burn-rate SLO compliance over the trailing window instead of instant queries. More statistically robust but complex to configure and explain.

---

## Decision

**Option B — Weighted probe set**, with the following design principles:

| Principle | Rationale |
|---|---|
| Pre-chaos probes abort if failing | Injecting chaos into an already-broken system is dangerous and produces meaningless results |
| During-chaos probes are observational | We expect degradation; we record *how much* |
| Post-chaos probes determine PASS/FAIL | The system must return to steady state within the recovery window |
| Probes span all three golden signals | Latency, traffic/errors, saturation — not just error rate |
| At least one probe per downstream dependency | Database, Kafka, inter-service — so a missed dependency isn't hidden |

**Recovery window**: 60 seconds. If the system hasn't recovered within 60s of chaos ending, the experiment fails. This matches Istio's default circuit-breaker ejection sleep.

---

## Consequences

- `analysis/steady-state.yaml` is the single source of truth for hypothesis definition
- `scripts/run-experiment.sh` reads this file at runtime — no hardcoded thresholds in scripts
- Adding a new service to the platform requires adding a corresponding steady-state probe
- Probe failures pre-chaos block the experiment and page on-call (via Alertmanager)
