#!/usr/bin/env bash
set -euo pipefail

# Installs Velero via Helm for backup/restore.
# Provider selection: aws|gcp|azure|minio (S3-compatible)
# For production, prefer workload identity / IRSA over static keys.
# Any values file that contains ${VAR} placeholders is rendered before Helm runs.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
ROOT_DIR="${COMMON_ROOT_DIR}"
cd "${ROOT_DIR}"

NAMESPACE="${NAMESPACE:-velero}"
PROVIDER="${PROVIDER:-minio}"
AUTH_MODE="${AUTH_MODE:-static}"
VER_VELERO="$(chart_version velero)"

# Sensible defaults for dev/local flows.
VELERO_BUCKET="${VELERO_BUCKET:-velero-backups}"
export VELERO_BUCKET

if [[ "${PROVIDER}" == "minio" ]]; then
  MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minio}"
  MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minio12345}"
  export MINIO_ACCESS_KEY MINIO_SECRET_KEY
fi

if [[ "${PROVIDER}" == "aws" ]]; then
  if [[ -z "${S3_REGION:-}" && -n "${AWS_REGION:-}" ]]; then
    S3_REGION="${AWS_REGION}"
  fi
  if [[ -z "${AWS_REGION:-}" && -n "${S3_REGION:-}" ]]; then
    AWS_REGION="${S3_REGION}"
  fi
  if [[ -z "${S3_ENDPOINT:-}" ]]; then
    S3_ENDPOINT="s3.${S3_REGION:-us-east-1}.amazonaws.com"
  fi
  S3_FORCE_PATH_STYLE="${S3_FORCE_PATH_STYLE:-false}"
  S3_INSECURE="${S3_INSECURE:-false}"
  export AWS_REGION S3_REGION S3_ENDPOINT S3_FORCE_PATH_STYLE S3_INSECURE
fi

cleanup() {
  if [[ -n "${TMP_WORK_DIR:-}" && -d "${TMP_WORK_DIR}" ]]; then
    rm -rf "${TMP_WORK_DIR}"
  fi
}
trap cleanup EXIT

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null
helm repo update >/dev/null

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

VALUES_BASE="k8s/helm-values/velero/velero-base.yaml"
VALUES_PROVIDER="k8s/helm-values/velero/velero-${PROVIDER}.yaml"

if [[ "${AUTH_MODE}" == "cloud" ]]; then
  case "${PROVIDER}" in
    aws) VALUES_PROVIDER="k8s/helm-values/velero/velero-aws-irsa.yaml" ;;
    gcp) VALUES_PROVIDER="k8s/helm-values/velero/velero-gcp-wi.yaml" ;;
    azure) VALUES_PROVIDER="k8s/helm-values/velero/velero-azure-wi.yaml" ;;
    minio) ;;
    *) echo "Unsupported PROVIDER for AUTH_MODE=cloud: ${PROVIDER}" >&2; exit 1 ;;
  esac
fi

if [[ ! -f "$VALUES_PROVIDER" ]]; then
  echo "Unsupported PROVIDER: $PROVIDER" >&2
  echo "Expected one of: aws|gcp|azure|minio" >&2
  exit 1
fi

RENDERED_VALUES_BASE="$(render_to_temp "$VALUES_BASE")"
RENDERED_VALUES_PROVIDER="$(render_to_temp "$VALUES_PROVIDER")"

helm upgrade --install velero vmware-tanzu/velero \
  --namespace "$NAMESPACE" \
  --version "$VER_VELERO" \
  -f "$RENDERED_VALUES_BASE" \
  -f "$RENDERED_VALUES_PROVIDER" \
  --atomic --timeout 15m

echo "Velero installed in namespace $NAMESPACE using provider $PROVIDER (auth: $AUTH_MODE)."
echo "Rendered values were generated from the selected overlays; missing env vars fail fast before Helm runs."
