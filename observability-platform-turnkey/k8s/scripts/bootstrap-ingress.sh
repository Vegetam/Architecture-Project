#!/usr/bin/env bash
set -euo pipefail

# Installs the recommended ingress controller for the selected cloud profile.
# Defaults:
# - EKS / AKS: install ingress-nginx
# - GKE: use the managed GKE Ingress controller (no in-cluster controller install)

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CLOUD_PROFILE="${CLOUD_PROFILE:-none}"
NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
RELEASE_NAME="${INGRESS_RELEASE_NAME:-ingress-nginx}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-$(chart_version ingressNginx)}"

case "${CLOUD_PROFILE}" in
  gke)
    echo "CLOUD_PROFILE=gke detected. Using managed GKE Ingress (class: gce). No ingress-nginx install is required."
    exit 0
    ;;
  eks|aks)
    ;;
  *)
    echo "No managed cloud ingress default for CLOUD_PROFILE=${CLOUD_PROFILE}. Skipping ingress controller install."
    exit 0
    ;;
esac

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update >/dev/null

helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
  --namespace "${NAMESPACE}" \
  --version "${INGRESS_NGINX_VERSION}" \
  --set controller.ingressClass="${INGRESS_CLASS_NAME}" \
  --set controller.ingressClassResource.name="${INGRESS_CLASS_NAME}" \
  --set controller.ingressClassResource.default=false \
  --set controller.service.externalTrafficPolicy=Local \
  --wait --timeout 10m

echo "Installed ingress-nginx for ${CLOUD_PROFILE} (IngressClass=${INGRESS_CLASS_NAME}, version=${INGRESS_NGINX_VERSION})."
