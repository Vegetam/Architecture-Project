#!/usr/bin/env bash
set -euo pipefail

# CI helper: render the selected overlays, then lint/template the upstream Helm charts.
# This catches unresolved ${VAR} placeholders and obvious values-schema breakage.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
ROOT_DIR="${COMMON_ROOT_DIR}"
cd "${ROOT_DIR}"

command -v helm >/dev/null 2>&1 || {
  echo "helm is required for validate-helm-render.sh" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_WORK_DIR:-}" && -d "${TMP_WORK_DIR}" ]]; then
    rm -rf "${TMP_WORK_DIR}"
  fi
  if [[ -n "${TMP_CHART_DIR:-}" && -d "${TMP_CHART_DIR}" ]]; then
    rm -rf "${TMP_CHART_DIR}"
  fi
}
trap cleanup EXIT

ensure_tmp_dir
TMP_CHART_DIR="$(mktemp -d)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null
helm repo update >/dev/null

# Dummy but syntactically valid values for render-time substitution.
export MINIO_ACCESS_KEY="minio"
export MINIO_SECRET_KEY="minio12345"
export S3_ENDPOINT="s3.eu-west-1.amazonaws.com"
export S3_REGION="eu-west-1"
export AWS_REGION="eu-west-1"
export S3_ACCESS_KEY_ID="dummy-access-key"
export S3_SECRET_ACCESS_KEY="dummy-secret-key"
export S3_FORCE_PATH_STYLE="false"
export S3_INSECURE="false"
export LOKI_S3_BUCKET_CHUNKS="loki-chunks"
export LOKI_S3_BUCKET_RULER="loki-ruler"
export LOKI_S3_BUCKET_ADMIN="loki-admin"
export TEMPO_S3_BUCKET="tempo-traces"
export AWS_IRSA_ROLE_ARN="arn:aws:iam::123456789012:role/observability-irsa"
export LOKI_GCS_BUCKET="loki-gcs"
export TEMPO_GCS_BUCKET="tempo-gcs"
export GCP_GSA_EMAIL="observability@example.iam.gserviceaccount.com"
export LOKI_AZURE_CONTAINER="loki"
export LOKI_AZURE_CONTAINER_CHUNKS="loki-chunks"
export LOKI_AZURE_CONTAINER_RULER="loki-ruler"
export LOKI_AZURE_CONTAINER_ADMIN="loki-admin"
export TEMPO_AZURE_CONTAINER="tempo"
export AZURE_STORAGE_ACCOUNT="observabilitystore"
export AZURE_STORAGE_ACCOUNT_KEY="dummy-storage-key"
export AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000"
export AZURE_RESOURCE_GROUP="observability-rg"
export VELERO_BUCKET="velero-backups"

pull_chart() {
  local chart_ref="$1"
  local version="$2"
  local chart_dir_name="$3"
  if [[ ! -d "${TMP_CHART_DIR}/${chart_dir_name}" ]]; then
    helm pull "$chart_ref" --version "$version" --untar --untardir "$TMP_CHART_DIR" >/dev/null
  fi
  printf '%s\n' "${TMP_CHART_DIR}/${chart_dir_name}"
}

validate_release() {
  local release_name="$1"
  local chart_key="$2"
  local chart_ref="$3"
  local chart_dir_name="$4"
  shift 4

  local version chart_dir
  version="$(chart_version "$chart_key")"
  chart_dir="$(pull_chart "$chart_ref" "$version" "$chart_dir_name")"

  helm lint "$chart_dir" "$@" >/dev/null
  helm template "$release_name" "$chart_ref" --version "$version" "$@" >/dev/null
  echo "OK: ${release_name} (${chart_ref}@${version})"
}

validate_minio_profile() {
  local kps_base kps_profile loki_base loki_provider loki_profile tempo_base tempo_provider tempo_profile grafana_base
  kps_base="$(render_to_temp k8s/helm-values/kube-prometheus-stack-values.yaml)"
  kps_profile="$(render_to_temp k8s/helm-values/profiles/prometheus-small.yaml)"
  loki_base="$(render_to_temp k8s/helm-values/loki-values.yaml)"
  loki_provider="$(render_to_temp k8s/helm-values/providers/loki-minio.yaml)"
  loki_profile="$(render_to_temp k8s/helm-values/profiles/loki-small.yaml)"
  tempo_base="$(render_to_temp k8s/helm-values/tempo-values.yaml)"
  tempo_provider="$(render_to_temp k8s/helm-values/providers/tempo-minio.yaml)"
  tempo_profile="$(render_to_temp k8s/helm-values/profiles/tempo-small.yaml)"
  grafana_base="$(render_to_temp k8s/helm-values/grafana-values.yaml)"

  validate_release kps-minio kubePrometheusStack prometheus-community/kube-prometheus-stack kube-prometheus-stack -f "$kps_base" -f "$kps_profile"
  validate_release loki-minio loki grafana/loki loki -f "$loki_base" -f "$loki_provider" -f "$loki_profile" --set loki.useTestSchema=true
  validate_release tempo-minio tempoDistributed grafana/tempo-distributed tempo-distributed -f "$tempo_base" -f "$tempo_provider" -f "$tempo_profile"
  validate_release grafana-minio grafana grafana/grafana grafana -f "$grafana_base"
}

validate_aws_cloud_profile() {
  local kps_base kps_profile kps_cloud loki_base loki_provider loki_profile loki_cloud tempo_base tempo_provider tempo_profile tempo_cloud grafana_base grafana_cloud velero_base velero_provider
  kps_base="$(render_to_temp k8s/helm-values/kube-prometheus-stack-values.yaml)"
  kps_profile="$(render_to_temp k8s/helm-values/profiles/prometheus-medium.yaml)"
  kps_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/kube-prometheus-stack-eks.yaml)"
  loki_base="$(render_to_temp k8s/helm-values/loki-values.yaml)"
  loki_provider="$(render_to_temp k8s/helm-values/providers/loki-aws-irsa.yaml)"
  loki_profile="$(render_to_temp k8s/helm-values/profiles/loki-medium.yaml)"
  loki_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/loki-eks.yaml)"
  tempo_base="$(render_to_temp k8s/helm-values/tempo-values.yaml)"
  tempo_provider="$(render_to_temp k8s/helm-values/providers/tempo-aws-irsa.yaml)"
  tempo_profile="$(render_to_temp k8s/helm-values/profiles/tempo-medium.yaml)"
  tempo_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/tempo-eks.yaml)"
  grafana_base="$(render_to_temp k8s/helm-values/grafana-values.yaml)"
  grafana_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/grafana-eks.yaml)"
  velero_base="$(render_to_temp k8s/helm-values/velero/velero-base.yaml)"
  velero_provider="$(render_to_temp k8s/helm-values/velero/velero-aws-irsa.yaml)"

  validate_release kps-aws kubePrometheusStack prometheus-community/kube-prometheus-stack kube-prometheus-stack -f "$kps_base" -f "$kps_profile" -f "$kps_cloud"
  validate_release loki-aws loki grafana/loki loki -f "$loki_base" -f "$loki_provider" -f "$loki_profile" -f "$loki_cloud" --set loki.useTestSchema=true
  validate_release tempo-aws tempoDistributed grafana/tempo-distributed tempo-distributed -f "$tempo_base" -f "$tempo_provider" -f "$tempo_profile" -f "$tempo_cloud"
  validate_release grafana-aws grafana grafana/grafana grafana -f "$grafana_base" -f "$grafana_cloud"
  validate_release velero-aws velero vmware-tanzu/velero velero -f "$velero_base" -f "$velero_provider"
}

validate_gcp_cloud_profile() {
  local loki_base loki_provider loki_profile loki_cloud tempo_base tempo_provider tempo_profile tempo_cloud
  loki_base="$(render_to_temp k8s/helm-values/loki-values.yaml)"
  loki_provider="$(render_to_temp k8s/helm-values/providers/loki-gcp-wi.yaml)"
  loki_profile="$(render_to_temp k8s/helm-values/profiles/loki-medium.yaml)"
  loki_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/loki-gke.yaml)"
  tempo_base="$(render_to_temp k8s/helm-values/tempo-values.yaml)"
  tempo_provider="$(render_to_temp k8s/helm-values/providers/tempo-gcp-wi.yaml)"
  tempo_profile="$(render_to_temp k8s/helm-values/profiles/tempo-medium.yaml)"
  tempo_cloud="$(render_to_temp k8s/helm-values/cloud-profiles/tempo-gke.yaml)"

  validate_release loki-gcp loki grafana/loki loki -f "$loki_base" -f "$loki_provider" -f "$loki_profile" -f "$loki_cloud" --set loki.useTestSchema=true
  validate_release tempo-gcp tempoDistributed grafana/tempo-distributed tempo-distributed -f "$tempo_base" -f "$tempo_provider" -f "$tempo_profile" -f "$tempo_cloud"
}

validate_minio_profile
validate_aws_cloud_profile
validate_gcp_cloud_profile

echo "Helm render validation completed successfully."
