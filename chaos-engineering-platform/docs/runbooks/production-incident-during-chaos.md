# Runbook — Production Incident During Chaos Experiment

**Trigger**: A production alert fires while a staging chaos experiment is running.

This runbook answers the question: *"Did the chaos experiment cause this, or is this a coincidence?"*

---

## Immediate Actions (< 2 minutes)

### 1. Stop all experiments immediately

```bash
# Kill everything in chaos-testing namespace
kubectl delete networkchaos,podchaos,stresschaos,iochaos --all -n chaos-testing

# Stop the LitmusChaos workflow if running
kubectl patch chaosengine resilience-gameday -n litmus \
  --type merge -p '{"spec":{"engineState":"stop"}}'
```

### 2. Confirm chaos is fully removed

```bash
kubectl get networkchaos,podchaos,stresschaos,iochaos -A
# Should return: No resources found.
```

### 3. Inform incident commander

Immediately post in the incident channel:
```
[CHAOS STOP] Chaos experiments halted at <time> due to production alert <alert-name>.
Chaos was running: <experiment-name> against staging namespace.
Experiments are now stopped. Investigating whether chaos contributed.
```

---

## Determining Cause

### Was it the chaos?

Chaos experiments in this platform target `microservices-staging` — they **cannot directly affect** the production `microservices` namespace due to:
- Namespace selectors in all experiment manifests
- The CI namespace safety check (see `.github/workflows/validate.yml`)
- Istio `AuthorizationPolicy` isolating staging from production traffic paths

**However**, indirect effects are possible:
- Shared Prometheus/Grafana overloaded by chaos metrics export
- Shared Kafka cluster (if not namespace-isolated) experiencing real packet loss
- Shared PostgreSQL (if staging and production share a cluster)

### Check shared infrastructure

```bash
# Is Kafka shared?
kubectl get kafkacluster -A

# Is PostgreSQL shared?
kubectl get externalsecret -n microservices -o yaml | grep -i postgres

# Prometheus memory/CPU (chaos metrics can spike usage)
kubectl top pod -n observability -l app.kubernetes.io/name=prometheus
```

---

## After the Incident

1. **Write an incident review** that explicitly addresses whether chaos contributed
2. **Add a safeguard** if chaos was a contributing factor:
   - Add a check in `run-experiment.sh` that verifies production alerts are clear before starting
   - Add a safeguard for any shared infrastructure identified above
3. **Resume the game day** only after the production incident is fully resolved and the RCA is complete

---

## Key Principle

> A chaos game day is never more important than a production incident.
> Stop chaos immediately, investigate, and resume later.
