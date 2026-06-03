#!/usr/bin/env bash
# ==============================================================================
# run-experiment.sh — Safe chaos experiment runner
#
# Usage:
#   ./scripts/run-experiment.sh <experiment-manifest.yaml> [--force]
#
# Safety checks:
#   1. Verify steady-state (Prometheus probes) BEFORE injecting chaos
#   2. Apply the experiment
#   3. Monitor Prometheus during the experiment
#   4. Verify steady-state AFTER chaos ends
#   5. Emit a resilience report
#
# The --force flag skips steady-state checks (useful for intentional break tests)
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

EXPERIMENT_FILE="${1:?Usage: $0 <experiment.yaml> [--force]}"
FORCE="${2:-}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
EXPERIMENT_NAME=$(basename "${EXPERIMENT_FILE}" .yaml)

[[ -f "${EXPERIMENT_FILE}" ]] || { error "File not found: ${EXPERIMENT_FILE}"; exit 1; }

# ── Prometheus query helper ───────────────────────────────────────────────────
prom_query() {
  local query="${1}"
  curl -sf "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode "query=${query}" | \
    python3 -c "import sys,json; data=json.load(sys.stdin); \
                results=data.get('data',{}).get('result',[]); \
                print(results[0]['value'][1] if results else 'NO_DATA')" 2>/dev/null || echo "ERROR"
}

# ── Steady-state verification ─────────────────────────────────────────────────
check_steady_state() {
  local phase="${1:-pre}"
  step "Checking steady-state (${phase}-chaos)..."
  local failures=0

  # order-service success rate
  ORDER_SR=$(prom_query 'sum(rate(otel_http_server_duration_count{service_name="order-service",http_status_code!~"5.."}[5m])) / sum(rate(otel_http_server_duration_count{service_name="order-service"}[5m]))')
  if python3 -c "import sys; sys.exit(0 if float('${ORDER_SR}') >= 0.99 else 1)" 2>/dev/null; then
    info "  order-service success rate: ${ORDER_SR} ✓"
  else
    error "  order-service success rate: ${ORDER_SR} ✗ (need >= 0.99)"
    failures=$((failures+1))
  fi

  # payment-service success rate
  PAYMENT_SR=$(prom_query 'sum(rate(otel_http_server_duration_count{service_name="payment-service",http_status_code!~"5.."}[5m])) / sum(rate(otel_http_server_duration_count{service_name="payment-service"}[5m]))')
  if python3 -c "import sys; sys.exit(0 if float('${PAYMENT_SR}') >= 0.99 else 1)" 2>/dev/null; then
    info "  payment-service success rate: ${PAYMENT_SR} ✓"
  else
    error "  payment-service success rate: ${PAYMENT_SR} ✗ (need >= 0.99)"
    failures=$((failures+1))
  fi

  # All pods ready
  NOT_READY=$(kubectl get pods -n microservices-staging \
    --field-selector='status.phase!=Running' --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "${NOT_READY}" -eq 0 ]]; then
    info "  All pods in microservices-staging: Ready ✓"
  else
    error "  ${NOT_READY} pod(s) not Ready in microservices-staging ✗"
    failures=$((failures+1))
  fi

  return "${failures}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Chaos Experiment Runner                             ║"
echo "║  Experiment: ${EXPERIMENT_NAME}"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Extract metadata from experiment file
RISK_LEVEL=$(python3 -c "import yaml; d=yaml.safe_load(open('${EXPERIMENT_FILE}')); print(d.get('metadata',{}).get('labels',{}).get('risk-level','unknown'))" 2>/dev/null || echo "unknown")
info "Risk level: ${RISK_LEVEL}"

# Refuse obvious production-targeted experiments unless explicitly allowed.
if grep -Eq '(^|[[:space:]-])microservices([[:space:]]|$)' "${EXPERIMENT_FILE}" \
  && ! grep -Eq 'microservices-staging' "${EXPERIMENT_FILE}"; then
  if [[ "${ALLOW_PRODUCTION_EXPERIMENTS:-no}" != "yes" ]]; then
    error "Refusing to run an experiment that targets the production namespace."
    error "Use staging manifests instead, or set ALLOW_PRODUCTION_EXPERIMENTS=yes if you truly intend this."
    exit 1
  fi
  warn "ALLOW_PRODUCTION_EXPERIMENTS=yes set — continuing against a production-targeted manifest."
fi

if [[ "${RISK_LEVEL}" == "high" && -z "${FORCE}" ]]; then
  warn "HIGH RISK experiment. This should only run in staging."
  warn "Environment check: $(kubectl config current-context)"
  read -rp "Are you sure? Type 'yes' to continue: " confirm
  [[ "${confirm}" == "yes" ]] || { info "Aborted."; exit 0; }
fi

# Pre-chaos steady state check
if [[ -z "${FORCE}" ]]; then
  if ! check_steady_state "pre"; then
    error "System is NOT in steady state. Aborting chaos experiment."
    error "Fix the existing issues before injecting chaos."
    exit 1
  fi
  info "Pre-chaos steady state: OK"
else
  warn "--force flag set. Skipping pre-chaos steady state check."
fi

# Port-forward Prometheus if not accessible
PROM_PF_PID=""
if ! curl -sf "${PROMETHEUS_URL}/-/healthy" &>/dev/null; then
  info "Port-forwarding Prometheus..."
  kubectl port-forward -n observability svc/prometheus 9090:9090 &
  PROM_PF_PID=$!
  sleep 3
fi

# Apply the experiment
step "Applying chaos experiment: ${EXPERIMENT_FILE}"
kubectl apply -f "${EXPERIMENT_FILE}"
START_TIME=$(date +%s)

# Extract duration from the experiment
DURATION=$(python3 -c "
import yaml, re
d = yaml.safe_load(open('${EXPERIMENT_FILE}'))
dur = d.get('spec',{}).get('duration','5m')
m = re.match(r'(\d+)m', dur)
print(int(m.group(1)) * 60 if m else 300)
" 2>/dev/null || echo "300")

info "Experiment running for ${DURATION}s. Monitoring..."
echo ""

# Monitor during experiment
INTERVAL=30
ELAPSED=0
while [[ ${ELAPSED} -lt ${DURATION} ]]; do
  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED+INTERVAL))
  REMAINING=$((DURATION-ELAPSED))

  ORDER_SR=$(prom_query 'sum(rate(otel_http_server_duration_count{service_name="order-service",http_status_code!~"5.."}[1m])) / sum(rate(otel_http_server_duration_count{service_name="order-service"}[1m]))')
  PAYMENT_SR=$(prom_query 'sum(rate(otel_http_server_duration_count{service_name="payment-service",http_status_code!~"5.."}[1m])) / sum(rate(otel_http_server_duration_count{service_name="payment-service"}[1m]))')
  P99=$(prom_query 'histogram_quantile(0.99, rate(otel_http_server_duration_bucket{service_name="order-service"}[1m]))')

  echo "[${ELAPSED}s/${DURATION}s] order-SR=${ORDER_SR} payment-SR=${PAYMENT_SR} p99=${P99}ms (${REMAINING}s remaining)"
done

# Experiment should be done; wait a bit for cleanup
info "Experiment complete. Waiting 60s for system to recover..."
sleep 60

# Post-chaos steady state check
echo ""
step "Post-chaos verification..."
POST_FAILURES=0
check_steady_state "post" || POST_FAILURES=$?

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME-START_TIME))

# Kill port-forward if we started it
[[ -n "${PROM_PF_PID}" ]] && kill "${PROM_PF_PID}" 2>/dev/null || true

# Resilience report
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Resilience Report                                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Experiment:    ${EXPERIMENT_NAME}"
echo "  Duration:      ${TOTAL_DURATION}s"
echo "  Risk level:    ${RISK_LEVEL}"
if [[ "${POST_FAILURES}" -eq 0 ]]; then
  echo -e "  Result:        ${GREEN}PASS — system recovered to steady state${NC}"
else
  echo -e "  Result:        ${RED}FAIL — ${POST_FAILURES} probe(s) still failing after recovery window${NC}"
  echo "  Action:        Review Grafana dashboards and Loki logs for root cause"
fi
echo ""
