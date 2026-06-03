#!/usr/bin/env bash
# ==============================================================================
# local-setup.sh — Create a local kind cluster with Chaos Mesh + mock services
#
# Prerequisites:
#   - Docker (running)
#   - kind    (https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
#   - kubectl
#   - helm
#
# What this script does:
#   1. Creates a kind cluster named "chaos-local"
#   2. Builds and loads the mock service Docker images into kind
#   3. Installs Chaos Mesh via Helm
#   4. Deploys the mock order-service and payment-service to the cluster
#   5. Installs a minimal Prometheus that scrapes both services
#   6. Prints port-forward commands so you can run experiments immediately
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

CLUSTER_NAME="chaos-local"
CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.6.3}"

# ── 1. Kind cluster ───────────────────────────────────────────────────────────
step "Creating kind cluster '${CLUSTER_NAME}'..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# ── 2. Build & load mock images ───────────────────────────────────────────────
step "Building mock service images..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

docker build -t mock-order-service:local   "${REPO_ROOT}/docker/mock-services/order-service"
docker build -t mock-payment-service:local "${REPO_ROOT}/docker/mock-services/payment-service"

step "Loading images into kind cluster..."
kind load docker-image mock-order-service:local   --name "${CLUSTER_NAME}"
kind load docker-image mock-payment-service:local --name "${CLUSTER_NAME}"

# ── 3. Namespaces ─────────────────────────────────────────────────────────────
step "Creating namespaces..."
kubectl create namespace microservices-staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chaos-mesh            --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chaos-testing         --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace observability         --dry-run=client -o yaml | kubectl apply -f -

# ── 4. Deploy mock services ───────────────────────────────────────────────────
step "Deploying mock services to microservices-staging..."
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: microservices-staging
  labels:
    app.kubernetes.io/name: order-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: order-service
    spec:
      containers:
        - name: order-service
          image: mock-order-service:local
          imagePullPolicy: Never
          ports:
            - containerPort: 3000
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 5
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: microservices-staging
spec:
  selector:
    app.kubernetes.io/name: order-service
  ports:
    - port: 3000
      targetPort: 3000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: microservices-staging
  labels:
    app.kubernetes.io/name: payment-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: payment-service
    spec:
      containers:
        - name: payment-service
          image: mock-payment-service:local
          imagePullPolicy: Never
          ports:
            - containerPort: 3001
          readinessProbe:
            httpGet: { path: /health, port: 3001 }
            initialDelaySeconds: 5
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: payment-service
  namespace: microservices-staging
spec:
  selector:
    app.kubernetes.io/name: payment-service
  ports:
    - port: 3001
      targetPort: 3001
EOF

kubectl rollout status deployment/order-service   -n microservices-staging --timeout=90s
kubectl rollout status deployment/payment-service -n microservices-staging --timeout=90s

# ── 5. Prometheus ─────────────────────────────────────────────────────────────
step "Installing Prometheus (kube-prometheus-stack minimal)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace observability \
  --set server.global.scrape_interval=10s \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false \
  --set nodeExporter.enabled=false \
  --set kubeStateMetrics.enabled=false \
  --set server.extraScrapeConfigs="
- job_name: order-service
  static_configs:
    - targets: ['order-service.microservices-staging.svc.cluster.local:3000']
  metrics_path: /metrics
- job_name: payment-service
  static_configs:
    - targets: ['payment-service.microservices-staging.svc.cluster.local:3001']
  metrics_path: /metrics
" \
  --wait --timeout 5m

# ── 6. Chaos Mesh ─────────────────────────────────────────────────────────────
step "Installing Chaos Mesh ${CHAOS_MESH_VERSION}..."
helm repo add chaos-mesh https://charts.chaos-mesh.org --force-update
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --version "${CHAOS_MESH_VERSION}" \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --wait --timeout 10m

# ── 7. RBAC for experiments ───────────────────────────────────────────────────
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Local chaos cluster is ready!                                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
info "Port-forward Prometheus (run in a separate terminal):"
echo "  kubectl port-forward -n observability svc/prometheus-server 9090:80"
echo ""
info "Port-forward Chaos Mesh dashboard (optional):"
echo "  kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333"
echo "  open http://localhost:2333"
echo ""
info "Run your first experiment:"
echo "  PROMETHEUS_URL=http://localhost:9090 \\"
echo "  ./scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml"
echo ""
info "Watch pods during chaos:"
echo "  watch kubectl get pods -n microservices-staging"
echo ""
info "Tear down when done:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
