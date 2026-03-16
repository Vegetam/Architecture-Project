#!/usr/bin/env bash
set -euo pipefail

# Applies optional security resources.
# NetworkPolicies remain cluster/CNI dependent; review before applying.
# Rendered manifests fail fast if required environment variables are missing.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
ROOT_DIR="${COMMON_ROOT_DIR}"
cd "${ROOT_DIR}"

OBS_NAMESPACE="${OBS_NAMESPACE:-observability}"
CLOUD_PROFILE="${CLOUD_PROFILE:-none}"
TLS_MODE="${TLS_MODE:-letsencrypt}"
APPLY_NETWORK_POLICIES="${APPLY_NETWORK_POLICIES:-true}"
APPLY_OTEL_MTLS_CERTS="${APPLY_OTEL_MTLS_CERTS:-true}"
APPLY_GRAFANA_INGRESS="${APPLY_GRAFANA_INGRESS:-true}"
APPLY_SELFSIGNED_ISSUER_FOR_OTEL_MTLS="${APPLY_SELFSIGNED_ISSUER_FOR_OTEL_MTLS:-true}"
LETSENCRYPT_SERVER="${LETSENCRYPT_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
GRAFANA_TLS_SECRET_NAME="${GRAFANA_TLS_SECRET_NAME:-grafana-tls}"
OTEL_COLLECTOR_SERVICE_NAME="${OTEL_COLLECTOR_SERVICE_NAME:-otel-collector}"

case "${CLOUD_PROFILE}" in
  gke) INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-gce}" ;;
  *) INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}" ;;
esac

case "${TLS_MODE}" in
  letsencrypt)
    CERT_ISSUER_KIND="${CERT_ISSUER_KIND:-cluster-issuer}"
    CERT_ISSUER_NAME="${CERT_ISSUER_NAME:-letsencrypt-prod}"
    ;;
  selfsigned)
    CERT_ISSUER_KIND="${CERT_ISSUER_KIND:-cluster-issuer}"
    CERT_ISSUER_NAME="${CERT_ISSUER_NAME:-selfsigned-issuer}"
    ;;
  none)
    CERT_ISSUER_KIND="${CERT_ISSUER_KIND:-cluster-issuer}"
    CERT_ISSUER_NAME="${CERT_ISSUER_NAME:-letsencrypt-prod}"
    ;;
  *)
    echo "Unsupported TLS_MODE: ${TLS_MODE}. Expected letsencrypt|selfsigned|none." >&2
    exit 1
    ;;
esac

export OBS_NAMESPACE INGRESS_CLASS_NAME CERT_ISSUER_KIND CERT_ISSUER_NAME GRAFANA_TLS_SECRET_NAME LETSENCRYPT_SERVER OTEL_COLLECTOR_SERVICE_NAME

if [[ "${TLS_MODE}" == "none" && "${APPLY_GRAFANA_INGRESS}" == "true" ]]; then
  echo "TLS_MODE=none is not supported with the standalone Grafana ingress manifest. Set APPLY_GRAFANA_INGRESS=false or use Helm-managed ingress." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${TMP_WORK_DIR:-}" && -d "${TMP_WORK_DIR}" ]]; then
    rm -rf "${TMP_WORK_DIR}"
  fi
}
trap cleanup EXIT

if [[ "${APPLY_NETWORK_POLICIES}" == "true" ]]; then
  kubectl apply -f k8s/manifests/networkpolicies/
fi

if [[ "${APPLY_SELFSIGNED_ISSUER_FOR_OTEL_MTLS}" == "true" || "${TLS_MODE}" == "selfsigned" ]]; then
  kubectl apply -f k8s/manifests/cert-manager/issuer-selfsigned.yaml
fi

if [[ "${APPLY_OTEL_MTLS_CERTS}" == "true" ]]; then
  kubectl apply -f "$(render_to_temp k8s/manifests/cert-manager/otel-mtls-certs.yaml)"
fi

if [[ "${TLS_MODE}" == "letsencrypt" ]]; then
  : "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL before applying the Lets Encrypt ClusterIssuer.}"
  export LETSENCRYPT_EMAIL
  kubectl apply -f "$(render_to_temp k8s/manifests/cert-manager/clusterissuer-letsencrypt-prod.yaml)"
fi

if [[ "${APPLY_GRAFANA_INGRESS}" == "true" ]]; then
  : "${GRAFANA_HOSTNAME:?Set GRAFANA_HOSTNAME before applying the Grafana ingress.}"
  export GRAFANA_HOSTNAME
  kubectl apply -f "$(render_to_temp k8s/manifests/ingress/grafana-ingress.yaml)"
fi

echo "Applied security manifests (TLS_MODE=${TLS_MODE}, INGRESS_CLASS_NAME=${INGRESS_CLASS_NAME})."
echo "Review NetworkPolicies for your CNI and ingress namespace before using strict production defaults."
