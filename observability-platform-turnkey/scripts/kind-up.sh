#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# kind-up.sh
# Spins up a local kind cluster and prints the recommended Helm installs.
# This script is intentionally conservative (it won't install charts by default).
# ------------------------------------------------------------------------------

echo "This repo's primary runnable environment is Docker Compose."
echo ""
echo "If you want to move toward Kubernetes, use Helm charts in k8s/README.md."
echo ""
echo "Suggested next step:"
echo "  1) Create a kind cluster:"
echo "     kind create cluster --name observability"
echo ""
echo "  2) Follow k8s/README.md to install charts (Prometheus/Loki/Tempo/Grafana/OTel)."
echo ""
echo "Tip: keep the compose stack for fast local development; use k8s for production-like testing."
