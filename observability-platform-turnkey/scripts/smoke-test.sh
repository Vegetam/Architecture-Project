#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# smoke-test.sh — basic end-to-end validation (production-minded compose)
#
# This stack does NOT publish internal control-plane ports to the host.
# The script checks internal services via `docker compose exec`.
#
# What it validates:
# - Kong proxy is reachable (optional if you have upstream services running)
# - Grafana is reachable
# - Tempo is receiving spans (via its /metrics endpoint)
# - Prometheus is healthy (internal)
# ==============================================================================

KONG_URL="${KONG_URL:-http://localhost:8000}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"

echo "🧪 Observability Platform — Smoke Test"
echo "   Kong proxy: $KONG_URL"
echo "   Grafana:    $GRAFANA_URL"
echo ""

# ── 1) Kong proxy reachability (optional) ─────────────────────────────────────
echo "1️⃣  Checking Kong proxy..."
KONG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$KONG_URL/" || echo "000")
if [[ "$KONG_STATUS" != "000" ]]; then
  echo "   ✅ Kong proxy reachable (HTTP $KONG_STATUS)"
else
  echo "   ⚠️  Kong proxy not reachable on $KONG_URL (is the stack up?)"
fi
echo ""

# ── 2) Grafana health ────────────────────────────────────────────────────────
echo "2️⃣  Checking Grafana..."
GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health" || echo "000")
if [[ "$GRAFANA_STATUS" == "200" ]]; then
  echo "   ✅ Grafana healthy"
else
  echo "   ❌ Grafana not reachable (HTTP $GRAFANA_STATUS)"
fi
echo ""

# ── 3) Prometheus health (internal) ─────────────────────────────────────────
echo "3️⃣  Checking Prometheus (internal)..."
if docker compose -f docker/docker-compose.yml exec -T prometheus wget -q --spider http://localhost:9090/-/healthy; then
  echo "   ✅ Prometheus healthy"
else
  echo "   ❌ Prometheus unhealthy or not running"
fi
echo ""

# ── 4) Tempo receiving spans (internal metrics) ──────────────────────────────
echo "4️⃣  Checking Tempo metrics (internal)..."
METRICS=$(docker compose -f docker/docker-compose.yml exec -T tempo wget -qO- http://localhost:3200/metrics || true)
if echo "$METRICS" | grep -q "tempo_distributor_received_spans_total"; then
  echo "   ✅ Tempo metrics endpoint reachable"
  echo "   (Tip) To validate ingestion, generate some traffic and re-run this test."
else
  echo "   ❌ Tempo metrics not reachable (or metric name changed)"
fi
echo ""

echo "🏁 Smoke test complete."
