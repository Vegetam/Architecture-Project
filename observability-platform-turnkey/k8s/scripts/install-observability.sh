#!/usr/bin/env bash
set -euo pipefail

# Installs the observability stack using pinned chart versions.
# Hybrid provider support:
#   PROVIDER=minio|aws|gcp|azure
# Sizing profiles:
#   PROFILE=small|medium|large
# Platform presets:
#   CLOUD_PROFILE=none|auto|eks|gke|aks
#
# Examples:
#   PROVIDER=minio PROFILE=small ./k8s/scripts/install-observability.sh
#   PROVIDER=aws   AUTH_MODE=cloud CLOUD_PROFILE=eks PROFILE=medium ./k8s/scripts/install-observability.sh
#   PROVIDER=gcp   AUTH_MODE=cloud CLOUD_PROFILE=gke PROFILE=medium ./k8s/scripts/install-observability.sh
#   PROVIDER=azure AUTH_MODE=cloud CLOUD_PROFILE=aks PROFILE=medium ./k8s/scripts/install-observability.sh
#
# Notes:
# - AUTH_MODE=static uses access keys from secrets (default).
# - AUTH_MODE=cloud uses cloud-native identity (IRSA/Workload Identity).
# - CLOUD_PROFILE adds platform defaults (storage class, topology spread, persistence).
# - INSTALL_INGRESS_CONTROLLER=auto installs ingress-nginx on EKS/AKS and skips it on GKE.
# - AUTO_STORAGE_CLASS=true detects the best available StorageClass when the expected cloud default is missing.
# - Any values file that contains ${VAR} placeholders is rendered before Helm runs.

# shellcheck source=./common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
ROOT_DIR="${COMMON_ROOT_DIR}"
cd "${ROOT_DIR}"

NAMESPACE="${NAMESPACE:-observability}"
PROVIDER="${PROVIDER:-minio}"
PROFILE="${PROFILE:-small}"
AUTH_MODE="${AUTH_MODE:-static}"
CLOUD_PROFILE="${CLOUD_PROFILE:-auto}"
INSTALL_INGRESS_CONTROLLER="${INSTALL_INGRESS_CONTROLLER:-auto}"
AUTO_STORAGE_CLASS="${AUTO_STORAGE_CLASS:-true}"
STORAGE_CLASS_OVERRIDE="${STORAGE_CLASS_OVERRIDE:-}"

VER_KPS="$(chart_version kubePrometheusStack)"
VER_GRAFANA="$(chart_version grafana)"
VER_LOKI="$(chart_version loki)"
VER_TEMPO="$(chart_version tempoDistributed)"
VER_OTEL="$(chart_version otelCollector)"
VER_PROMTAIL="$(chart_version promtail)"

# Sensible defaults for common turnkey flows.
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

map_auto_cloud_profile() {
  case "$1" in
    aws) echo "eks" ;;
    gcp) echo "gke" ;;
    azure) echo "aks" ;;
    *) echo "none" ;;
  esac
}

preferred_storage_class() {
  case "$1" in
    eks) echo "gp3" ;;
    gke) echo "premium-rwo" ;;
    aks) echo "managed-premium" ;;
    *) echo "" ;;
  esac
}

storage_candidates() {
  case "$1" in
    eks) echo "gp3 gp2 ebs-csi-gp3 ebs-sc standard" ;;
    gke) echo "premium-rwo standard-rwo standard premium-rwo-retain balanced-rwo" ;;
    aks) echo "managed-premium managed-csi managed premium-ssd default" ;;
    *) echo "" ;;
  esac
}

storage_class_exists() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  kubectl get storageclass "$name" >/dev/null 2>&1
}

default_storage_class() {
  kubectl get storageclass \
    -o custom-columns=NAME:.metadata.name,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class \
    --no-headers 2>/dev/null | awk '$2 == "true" {print $1; exit}'
}

first_storage_class() {
  kubectl get storageclass -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | awk 'NR==1 {print $1; exit}'
}

detect_storage_class() {
  local profile_name="$1"
  local preferred candidates default_sc first_sc candidate

  if [[ -n "${STORAGE_CLASS_OVERRIDE}" ]]; then
    if storage_class_exists "${STORAGE_CLASS_OVERRIDE}"; then
      echo "${STORAGE_CLASS_OVERRIDE}"
      return 0
    fi
    echo "StorageClass override not found: ${STORAGE_CLASS_OVERRIDE}" >&2
    return 1
  fi

  preferred="$(preferred_storage_class "${profile_name}")"
  if storage_class_exists "${preferred}"; then
    echo "${preferred}"
    return 0
  fi

  candidates="$(storage_candidates "${profile_name}")"
  for candidate in ${candidates}; do
    if storage_class_exists "${candidate}"; then
      echo "${candidate}"
      return 0
    fi
  done

  default_sc="$(default_storage_class || true)"
  if [[ -n "${default_sc}" ]] && storage_class_exists "${default_sc}"; then
    echo "${default_sc}"
    return 0
  fi

  first_sc="$(first_storage_class || true)"
  if [[ -n "${first_sc}" ]]; then
    echo "${first_sc}"
    return 0
  fi

  return 1
}

write_storage_overrides() {
  local storage_class="$1"
  ensure_tmp_dir

  cat > "${TMP_WORK_DIR}/kps-storageclass.yaml" <<EOF2
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${storage_class}
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${storage_class}
EOF2

  cat > "${TMP_WORK_DIR}/loki-storageclass.yaml" <<EOF2
loki:
  write:
    persistence:
      storageClass: ${storage_class}
  backend:
    persistence:
      storageClass: ${storage_class}
EOF2

  cat > "${TMP_WORK_DIR}/tempo-storageclass.yaml" <<EOF2
ingester:
  persistence:
    enabled: true
    storageClass: ${storage_class}
compactor:
  persistence:
    enabled: true
    storageClass: ${storage_class}
EOF2

  cat > "${TMP_WORK_DIR}/grafana-storageclass.yaml" <<EOF2
persistence:
  enabled: true
  type: pvc
  storageClassName: ${storage_class}
EOF2
}

render_value_file() {
  local src="$1"
  [[ -f "$src" ]] || {
    echo "Missing values file: $src" >&2
    exit 1
  }
  render_to_temp "$src"
}

# Auto-map managed cloud providers to their Kubernetes distribution profile.
if [[ "${CLOUD_PROFILE}" == "auto" ]]; then
  CLOUD_PROFILE="$(map_auto_cloud_profile "${PROVIDER}")"
fi

# Per-cloud ingress default:
# - EKS / AKS: install ingress-nginx by default
# - GKE: rely on managed GKE Ingress by default
if [[ "${INSTALL_INGRESS_CONTROLLER}" == "auto" ]]; then
  case "${CLOUD_PROFILE}" in
    eks|aks) INSTALL_INGRESS_CONTROLLER="true" ;;
    *) INSTALL_INGRESS_CONTROLLER="false" ;;
  esac
fi

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

if [[ "${INSTALL_INGRESS_CONTROLLER}" == "true" ]]; then
  CLOUD_PROFILE="${CLOUD_PROFILE}" "${SCRIPT_DIR}/bootstrap-ingress.sh"
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null

LOKI_PROVIDER_VALUES="k8s/helm-values/providers/loki-${PROVIDER}.yaml"
TEMPO_PROVIDER_VALUES="k8s/helm-values/providers/tempo-${PROVIDER}.yaml"

if [[ "${AUTH_MODE}" == "cloud" ]]; then
  case "${PROVIDER}" in
    aws)
      LOKI_PROVIDER_VALUES="k8s/helm-values/providers/loki-aws-irsa.yaml"
      TEMPO_PROVIDER_VALUES="k8s/helm-values/providers/tempo-aws-irsa.yaml"
      ;;
    gcp)
      LOKI_PROVIDER_VALUES="k8s/helm-values/providers/loki-gcp-wi.yaml"
      TEMPO_PROVIDER_VALUES="k8s/helm-values/providers/tempo-gcp-wi.yaml"
      ;;
    azure)
      LOKI_PROVIDER_VALUES="k8s/helm-values/providers/loki-azure-wi.yaml"
      TEMPO_PROVIDER_VALUES="k8s/helm-values/providers/tempo-azure-wi.yaml"
      ;;
    minio)
      ;;
    *)
      echo "Unsupported PROVIDER for AUTH_MODE=cloud: ${PROVIDER}" >&2
      exit 1
      ;;
  esac
fi

KPS_PROFILE_VALUES="k8s/helm-values/profiles/prometheus-${PROFILE}.yaml"
LOKI_PROFILE_VALUES="k8s/helm-values/profiles/loki-${PROFILE}.yaml"
TEMPO_PROFILE_VALUES="k8s/helm-values/profiles/tempo-${PROFILE}.yaml"

KPS_CLOUD_VALUES=""
LOKI_CLOUD_VALUES=""
TEMPO_CLOUD_VALUES=""
GRAFANA_CLOUD_VALUES=""
if [[ "${CLOUD_PROFILE}" != "none" ]]; then
  KPS_CLOUD_VALUES="k8s/helm-values/cloud-profiles/kube-prometheus-stack-${CLOUD_PROFILE}.yaml"
  LOKI_CLOUD_VALUES="k8s/helm-values/cloud-profiles/loki-${CLOUD_PROFILE}.yaml"
  TEMPO_CLOUD_VALUES="k8s/helm-values/cloud-profiles/tempo-${CLOUD_PROFILE}.yaml"
  GRAFANA_CLOUD_VALUES="k8s/helm-values/cloud-profiles/grafana-${CLOUD_PROFILE}.yaml"
fi

KPS_STORAGE_VALUES=""
LOKI_STORAGE_VALUES=""
TEMPO_STORAGE_VALUES=""
GRAFANA_STORAGE_VALUES=""
if [[ "${CLOUD_PROFILE}" != "none" && "${AUTO_STORAGE_CLASS}" == "true" ]]; then
  if SELECTED_STORAGE_CLASS="$(detect_storage_class "${CLOUD_PROFILE}")"; then
    write_storage_overrides "${SELECTED_STORAGE_CLASS}"
    KPS_STORAGE_VALUES="${TMP_WORK_DIR}/kps-storageclass.yaml"
    LOKI_STORAGE_VALUES="${TMP_WORK_DIR}/loki-storageclass.yaml"
    TEMPO_STORAGE_VALUES="${TMP_WORK_DIR}/tempo-storageclass.yaml"
    GRAFANA_STORAGE_VALUES="${TMP_WORK_DIR}/grafana-storageclass.yaml"
    echo "Using StorageClass: ${SELECTED_STORAGE_CLASS}"
  else
    echo "No StorageClass detected. Continuing with cloud-profile defaults." >&2
  fi
fi

base_kps_values="$(render_value_file k8s/helm-values/kube-prometheus-stack-values.yaml)"
base_loki_values="$(render_value_file k8s/helm-values/loki-values.yaml)"
base_tempo_values="$(render_value_file k8s/helm-values/tempo-values.yaml)"
base_otel_values="$(render_value_file k8s/helm-values/otel-collector-mtls-values.yaml)"
base_promtail_values="$(render_value_file k8s/helm-values/promtail-values.yaml)"
base_grafana_values="$(render_value_file k8s/helm-values/grafana-values.yaml)"

kps_profile_values="$(render_value_file "${KPS_PROFILE_VALUES}")"
loki_provider_values="$(render_value_file "${LOKI_PROVIDER_VALUES}")"
loki_profile_values="$(render_value_file "${LOKI_PROFILE_VALUES}")"
tempo_provider_values="$(render_value_file "${TEMPO_PROVIDER_VALUES}")"
tempo_profile_values="$(render_value_file "${TEMPO_PROFILE_VALUES}")"

kps_cloud_values=""
loki_cloud_values=""
tempo_cloud_values=""
grafana_cloud_values=""
if [[ -n "${KPS_CLOUD_VALUES}" ]]; then
  kps_cloud_values="$(render_value_file "${KPS_CLOUD_VALUES}")"
  loki_cloud_values="$(render_value_file "${LOKI_CLOUD_VALUES}")"
  tempo_cloud_values="$(render_value_file "${TEMPO_CLOUD_VALUES}")"
  grafana_cloud_values="$(render_value_file "${GRAFANA_CLOUD_VALUES}")"
fi

kps_args=(
  upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack
  --namespace "$NAMESPACE"
  --version "$VER_KPS"
  -f "$base_kps_values"
  -f "$kps_profile_values"
)
if [[ -n "$kps_cloud_values" ]]; then
  kps_args+=( -f "$kps_cloud_values" )
fi
if [[ -n "$KPS_STORAGE_VALUES" ]]; then
  kps_args+=( -f "$KPS_STORAGE_VALUES" )
fi
kps_args+=( --atomic --timeout 15m )
helm "${kps_args[@]}"

loki_args=(
  upgrade --install loki grafana/loki
  --namespace "$NAMESPACE"
  --version "$VER_LOKI"
  -f "$base_loki_values"
  -f "$loki_provider_values"
  -f "$loki_profile_values"
)
if [[ -n "$loki_cloud_values" ]]; then
  loki_args+=( -f "$loki_cloud_values" )
fi
if [[ -n "$LOKI_STORAGE_VALUES" ]]; then
  loki_args+=( -f "$LOKI_STORAGE_VALUES" )
fi
loki_args+=( --atomic --timeout 15m )
helm "${loki_args[@]}"

tempo_args=(
  upgrade --install tempo-distributed grafana/tempo-distributed
  --namespace "$NAMESPACE"
  --version "$VER_TEMPO"
  -f "$base_tempo_values"
  -f "$tempo_provider_values"
  -f "$tempo_profile_values"
)
if [[ -n "$tempo_cloud_values" ]]; then
  tempo_args+=( -f "$tempo_cloud_values" )
fi
if [[ -n "$TEMPO_STORAGE_VALUES" ]]; then
  tempo_args+=( -f "$TEMPO_STORAGE_VALUES" )
fi
tempo_args+=( --atomic --timeout 15m )
helm "${tempo_args[@]}"

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace "$NAMESPACE" \
  --version "$VER_OTEL" \
  -f "$base_otel_values" \
  --atomic --timeout 10m

helm upgrade --install promtail grafana/promtail \
  --namespace "$NAMESPACE" \
  --version "$VER_PROMTAIL" \
  -f "$base_promtail_values" \
  --atomic --timeout 10m

grafana_args=(
  upgrade --install grafana grafana/grafana
  --namespace "$NAMESPACE"
  --version "$VER_GRAFANA"
  -f "$base_grafana_values"
)
if [[ -n "$grafana_cloud_values" ]]; then
  grafana_args+=( -f "$grafana_cloud_values" )
fi
if [[ -n "$GRAFANA_STORAGE_VALUES" ]]; then
  grafana_args+=( -f "$GRAFANA_STORAGE_VALUES" )
fi
grafana_args+=( --atomic --timeout 10m )
helm "${grafana_args[@]}"

kubectl apply -f k8s/manifests/prometheus-rules/ || true
kubectl apply -f k8s/manifests/servicemonitors/ || true

echo "Installed observability stack into namespace $NAMESPACE."
echo "Provider: $PROVIDER | Profile: $PROFILE | Auth: $AUTH_MODE | Cloud profile: $CLOUD_PROFILE"
echo "Ingress controller auto-install: $INSTALL_INGRESS_CONTROLLER | StorageClass auto-detect: $AUTO_STORAGE_CLASS"
echo "Optional: apply network policies with: k8s/scripts/apply-security.sh"
echo "Optional: install Velero + run restore drill: k8s/scripts/install-velero.sh && k8s/scripts/restore-drill.sh"
