#!/usr/bin/env bash
set -euo pipefail

# Dev/test only. Use managed object storage in production.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
ROOT_DIR="${COMMON_ROOT_DIR}"
cd "${ROOT_DIR}"

NAMESPACE="${NAMESPACE:-observability}"
MINIO_VERSION="$(chart_version minio)"

# --------------------------------------------------------------------------
# Credentials: read from env vars — never fall back to insecure defaults.
# Set MINIO_ROOT_USER and MINIO_ROOT_PASSWORD in your .env file.
# --------------------------------------------------------------------------
if [[ -z "${MINIO_ROOT_USER:-}" ]]; then
  echo "ERROR: MINIO_ROOT_USER is not set. Add it to your .env file." >&2
  exit 1
fi
if [[ -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
  echo "ERROR: MINIO_ROOT_PASSWORD is not set. Add it to your .env file." >&2
  exit 1
fi
if [[ "${#MINIO_ROOT_PASSWORD}" -lt 16 ]]; then
  echo "ERROR: MINIO_ROOT_PASSWORD must be at least 16 characters." >&2
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo update >/dev/null

helm upgrade --install minio bitnami/minio \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --version "$MINIO_VERSION" \
  -f k8s/helm-values/minio-values.yaml \
  --set auth.rootUser="${MINIO_ROOT_USER}" \
  --set auth.rootPassword="${MINIO_ROOT_PASSWORD}"

echo "MinIO installed in namespace $NAMESPACE (version ${MINIO_VERSION})."
