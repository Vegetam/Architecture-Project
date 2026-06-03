# ADR 001 — Chaos Engineering: Chaos Mesh vs LitmusChaos vs Gremlin

**Status**: Accepted — Use Both (different roles)
**Date**: 2024-02-01

---

## Context

The platform needs chaos engineering to validate resilience before production releases and continuously in staging. Key requirements:
- Fault injection at network, pod, CPU, memory, and disk I/O levels
- Integration with Prometheus (the same Prometheus driving Argo Rollouts analysis)
- Ability to define "pass/fail" criteria based on SLOs
- GitOps-compatible (experiments as YAML in git)

---

## Options

### Option A: Chaos Mesh alone
CNCF project. Rich fault types (NetworkChaos, PodChaos, StressChaos, IOChaos, TimeChaos, DNSChaos). Web dashboard. Experiments as Kubernetes CRDs.

### Option B: LitmusChaos alone
CNCF graduated. ChaosWorkflows for sequenced experiments. Resilience Score calculation. ChaosHub library.

### Option C: Gremlin (SaaS)
Commercial. Best UX. Expensive. SaaS dependency.

### Option D: Both Chaos Mesh + LitmusChaos

---

## Decision

**Use both Chaos Mesh and LitmusChaos with distinct roles:**

| Tool | Role |
|---|---|
| **Chaos Mesh** | Individual fault experiments (network latency, pod kill, stress). Run ad-hoc or from CI. |
| **LitmusChaos** | Orchestrated game days (ChaosWorkflow sequences multiple experiments). Resilience Score tracking over time. |

**Why both:**
- Chaos Mesh has richer fault types (especially IOChaos and NetworkChaos with fine-grained control)
- LitmusChaos has superior workflow orchestration and the Resilience Score concept (quantified chaos results)
- They are complementary, not competing

---

## Consequences

- All experiments are GitOps-managed YAML in this repo
- The CI validates that HIGH RISK experiments can only target staging namespaces
- `scripts/run-experiment.sh` enforces steady-state checks before/after every experiment
- Chaos Mesh dashboard and LitmusChaos portal are restricted to private IP ranges (no public access)
- Game day resilience scores are tracked in LitmusChaos and emitted as Prometheus metrics → Grafana
