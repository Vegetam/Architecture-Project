#!/usr/bin/env bash
set -euo pipefail

# Installs cert-manager if it's not present.
# Version is pinned in k8s/versions.yaml.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_VERSION="$(chart_version certManager)"

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo update >/dev/null

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace "$NAMESPACE" \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait --timeout 10m

echo "cert-manager installed (version ${CERT_MANAGER_VERSION})."
