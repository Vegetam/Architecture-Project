#!/usr/bin/env bash
# ==============================================================================
# chaos-engineering-platform bootstrap.sh
# Installs Chaos Mesh + LitmusChaos and creates the chaos-testing namespace.
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.6.3}"
LITMUS_VERSION="${LITMUS_VERSION:-3.6.1}"

# ── Namespaces ────────────────────────────────────────────────────────────────
info "Creating namespaces..."
kubectl create namespace chaos-mesh    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace litmus        --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chaos-testing --dry-run=client -o yaml | kubectl apply -f -

# chaos-testing namespace is where experiments run — must NOT have Istio injection
# (Chaos Mesh injects its own network namespace manipulation)
kubectl label namespace chaos-testing istio-injection=disabled --overwrite

# ── Chaos Mesh ────────────────────────────────────────────────────────────────
info "Installing Chaos Mesh ${CHAOS_MESH_VERSION}..."
helm repo add chaos-mesh https://charts.chaos-mesh.org --force-update
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --version "${CHAOS_MESH_VERSION}" \
  --values chaos-mesh/install/chaos-mesh-values.yaml \
  --set chaosDaemon.runtime=containerd \
  --wait --timeout 10m

info "Chaos Mesh dashboard: https://chaos.vegetam.io"
info "Or: kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333"

# ── LitmusChaos ───────────────────────────────────────────────────────────────
info "Installing LitmusChaos ${LITMUS_VERSION}..."
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ --force-update
helm upgrade --install litmus litmuschaos/litmus \
  --namespace litmus \
  --version "${LITMUS_VERSION}" \
  --values litmus/install/litmus-values.yaml \
  --wait --timeout 10m

info "LitmusChaos portal: https://litmus.vegetam.io"
info "Use your SSO/IdP-backed authentication configuration before exposing the Litmus portal."

# ── RBAC for experiments ──────────────────────────────────────────────────────
info "Applying experiment RBAC..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: chaos-runner
  namespace: chaos-testing
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: chaos-runner
rules:
  - apiGroups: [chaos-mesh.org]
    resources: ["*"]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [pods, services, endpoints]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: chaos-runner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: chaos-runner
subjects:
  - kind: ServiceAccount
    name: chaos-runner
    namespace: chaos-testing
EOF

info ""
info "Bootstrap complete."
info ""
info "Run your first experiment:"
info "  ./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml"
info ""
info "Or run the full resilience game day:"
info "  kubectl apply -f litmus/workflows/resilience-gameday.yaml"
