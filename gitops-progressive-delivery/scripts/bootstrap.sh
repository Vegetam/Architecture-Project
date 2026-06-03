#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh — One-command setup for a new cluster
#
# Usage:
#   export ARGOCD_HOSTNAME=argocd.example.com
#   export CLUSTER=your-kubecontext
#   ./scripts/bootstrap.sh
#
# What it does:
#   1. Installs cert-manager
#   2. Installs ingress-nginx
#   3. Installs ArgoCD
#   4. Installs Argo Rollouts
#   5. Applies the App of Apps (hands off to GitOps from here)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Validate required env vars ────────────────────────────────────────────────
: "${ARGOCD_HOSTNAME:?Set ARGOCD_HOSTNAME (e.g. argocd.example.com)}"
: "${CLUSTER:?Set CLUSTER to your kubecontext name}"

echo "========================================"
echo " Bootstrapping GitOps platform"
echo " Cluster:  ${CLUSTER}"
echo " ArgoCD:   https://${ARGOCD_HOSTNAME}"
echo "========================================"

kubectl config use-context "${CLUSTER}"

# ── 1. cert-manager ───────────────────────────────────────────────────────────
echo ""
echo "→ Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.5 \
  --set installCRDs=true \
  --wait
echo "  cert-manager ready."

# ── 2. ingress-nginx ──────────────────────────────────────────────────────────
echo ""
echo "→ Installing ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.10.0 \
  --wait
echo "  ingress-nginx ready."

# ── 3. ArgoCD ─────────────────────────────────────────────────────────────────
echo ""
echo "→ Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update >/dev/null

# Substitute ARGOCD_HOSTNAME into values before installing
envsubst < "${ROOT_DIR}/argocd/install/argocd-values.yaml" > /tmp/argocd-values-rendered.yaml

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 7.3.11 \
  -f /tmp/argocd-values-rendered.yaml \
  --wait
echo "  ArgoCD ready."

# ── 4. Argo Rollouts ──────────────────────────────────────────────────────────
echo ""
echo "→ Installing Argo Rollouts..."
envsubst < "${ROOT_DIR}/argo-rollouts/install/rollouts-values.yaml" > /tmp/rollouts-values-rendered.yaml

helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  --version 2.37.6 \
  -f /tmp/rollouts-values-rendered.yaml \
  --wait
echo "  Argo Rollouts ready."

# ── 5. App of Apps ────────────────────────────────────────────────────────────
echo ""
echo "→ Applying App of Apps (GitOps takes over from here)..."
kubectl apply -f "${ROOT_DIR}/argocd/apps/app-of-apps.yaml"
echo "  App of Apps applied."

# ── Done ──────────────────────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "========================================"
echo " Bootstrap complete!"
echo ""
echo " ArgoCD UI:       https://${ARGOCD_HOSTNAME}"
echo " Username:        admin"
echo " Initial password: ${ARGOCD_PASSWORD}"
echo ""
echo " Change the password immediately:"
echo "   argocd login ${ARGOCD_HOSTNAME}"
echo "   argocd account update-password"
echo ""
echo " ArgoCD will now sync all apps from git."
echo " Monitor: kubectl get applications -n argocd"
echo "========================================"
