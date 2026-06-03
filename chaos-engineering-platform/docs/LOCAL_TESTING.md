# Local Testing Guide

Two modes depending on what you want to test:

---

## Mode 1 — Docker only (no Kubernetes)

Verifies steady-state checks, Prometheus queries, and Grafana dashboards.
**Cannot inject chaos** (Chaos Mesh needs Kubernetes) but lets you confirm the monitoring stack works.

**Prerequisites**: Docker Desktop

```bash
# Start the stack
docker compose -f docker/docker-compose.yml up -d

# Verify services are healthy
curl http://localhost:3000/health    # {"status":"ok","service":"order-service"}
curl http://localhost:3001/health    # {"status":"ok","service":"payment-service"}

# Check Prometheus is scraping metrics (wait ~30s for first scrape)
# open http://localhost:9090
# Query: otel_http_server_duration_count{service_name="order-service"}
# Should return data immediately (the mock services emit background traffic)

# Open Grafana — dashboards auto-provisioned
# open http://localhost:3030   (admin / admin)
# → Chaos Engineering / Chaos Resilience Platform

# Run the steady-state check against the local stack
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml --force
# Expected: steady-state probes print values, experiment skips (no k8s cluster)

# Stop
docker compose -f docker/docker-compose.yml down
```

---

## Mode 2 — kind cluster (full chaos injection)

Runs real Chaos Mesh experiments against the mock services inside a local Kubernetes cluster.

**Prerequisites**: Docker Desktop + [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) + kubectl + helm

```bash
# One-time setup (~5 minutes)
./scripts/local-setup.sh
```

After setup completes, open **two terminals**:

**Terminal 1 — Port-forward Prometheus:**
```bash
kubectl port-forward -n observability svc/prometheus-server 9090:80
```

**Terminal 2 — Run an experiment:**
```bash
# Verify steady state first
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml

# Watch pods in another window
watch kubectl get pods -n microservices-staging
```

### What to observe during chaos

| What | Where |
|---|---|
| Pods affected | `kubectl get pods -n microservices-staging` |
| Chaos resource state | `kubectl get networkchaos -n chaos-testing` |
| Prometheus metrics | `http://localhost:9090` → query `otel_http_server_duration_count` |
| Grafana dashboard | Port-forward Grafana: `kubectl port-forward -n observability svc/prometheus-grafana 3030:80` |
| Experiment verdict | `run-experiment.sh` output — PASS/FAIL printed at the end |

### Try each experiment

```bash
# Low risk — network latency
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml

# Low risk — pod kill (watch one pod restart)
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/pod/pod-kill-order-service.yaml

# Medium risk — CPU stress
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/stress/cpu-stress-payment.yaml

# Medium risk — HTTP error injection (20% 503s on POST /orders)
PROMETHEUS_URL=http://localhost:9090 \
  ./scripts/run-experiment.sh chaos-mesh/experiments/http/http-error-order.yaml
```

### Emergency stop

```bash
# Remove all active chaos experiments immediately
make clean-experiments
```

### Tear down

```bash
kind delete cluster --name chaos-local
```

---

## Upgrading to real microservices

When you want to test against your actual `microservices-ddd-kafka` services instead of mocks:

1. Start `microservices-ddd-kafka` with its `docker-compose.yml`
2. Run `./scripts/local-setup.sh` but skip the mock service deployment step (comment out step 4)
3. Point `PROMETHEUS_URL` at the observability-platform-turnkey Prometheus instead

The experiments don't need changes — they target `microservices-staging` namespace labels, which the real services also use.
