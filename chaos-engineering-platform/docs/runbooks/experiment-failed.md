# Runbook — Chaos Experiment Failed

**Trigger**: `run-experiment.sh` exits non-zero, or a LitmusChaos probe verdict is `Fail`.

---

## Immediate Actions

### 1. Stop the experiment

```bash
# Delete the active chaos resource (use the name from the experiment YAML)
kubectl delete networkchaos <name> -n chaos-testing 2>/dev/null
kubectl delete podchaos     <name> -n chaos-testing 2>/dev/null
kubectl delete stresschaos  <name> -n chaos-testing 2>/dev/null
kubectl delete iochaos      <name> -n chaos-testing 2>/dev/null

# Or delete everything in chaos-testing if you're unsure
kubectl delete networkchaos,podchaos,stresschaos,iochaos --all -n chaos-testing
```

### 2. Verify the system is recovering

```bash
# Check pod health
kubectl get pods -n microservices-staging

# Check success rates (wait 2 minutes for Prometheus to reflect recovery)
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(otel_http_server_duration_count{service_name="order-service",http_status_code!~"5.."}[2m])) / sum(rate(otel_http_server_duration_count{service_name="order-service"}[2m]))' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1])"
```

### 3. Check Loki for root cause

```logql
# All errors from the affected service during the experiment window
{namespace="microservices-staging", app="order-service"} |= "error" | json
```

---

## Common Failure Patterns

### System didn't recover within 60s

**Cause**: The fault type caused a cascading failure or data corruption that the service can't self-heal from.

**Actions**:
1. Check if any saga compensations are stuck: `kubectl get sagastate -n microservices-staging`
2. Check Kafka consumer lag: `kubectl exec -n kafka kafka-0 -- kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups`
3. If compensation is stuck, trigger manual compensation: `./scripts/run-experiment.sh` in dry-run mode

**Resolution**: Rolling restart of affected services, then re-run steady-state check.

---

### Pod OOMKilled during memory stress

**Cause**: Memory limit was hit before the experiment ended (expected for `memory-stress-order.yaml`).

**Actions**:
1. This is expected behaviour — verify OOMKill shows in Loki
2. Verify the pod restarted cleanly: `kubectl describe pod -n microservices-staging -l app.kubernetes.io/name=order-service`
3. Record the memory watermark as a finding: the current `resources.limits.memory` may be too tight

---

### Steady-state check failed pre-chaos

**Cause**: The system was already degraded before the experiment started.

**Actions**:
1. Do NOT run the experiment
2. Check for active Alertmanager alerts: `kubectl port-forward -n observability svc/alertmanager 9093:9093`
3. Resolve the underlying issue first
4. Re-run `./scripts/run-experiment.sh <manifest>` after the system is healthy

---

## After Resolving

```bash
# Re-run the steady-state check manually
./scripts/run-experiment.sh analysis/steady-state.yaml --check-only

# If system is healthy, re-run the failed experiment
./scripts/run-experiment.sh <experiment-that-failed.yaml>
```

Document the failure and root cause in the team's resilience tracking notes.
