#!/usr/bin/env bash
# ==============================================================================
# promote.sh — Promote a canary rollout or sync production after image update
#
# Usage:
#   # Promote a paused canary (payment-service blue/green manual promotion):
#   ./scripts/promote.sh rollout payment-service
#
#   # Sync production after CI updated the image tag:
#   ./scripts/promote.sh production
#
#   # Abort a bad canary:
#   ./scripts/promote.sh abort order-service
# ==============================================================================
set -euo pipefail

NAMESPACE="${NAMESPACE:-microservices}"
ARGOCD_APP="microservices-production"

action="${1:-}"
target="${2:-}"

case "$action" in
  rollout)
    : "${target:?Usage: promote.sh rollout <service-name>}"
    echo "→ Promoting rollout: ${target} in ${NAMESPACE}"
    kubectl argo rollouts promote "${target}" -n "${NAMESPACE}"
    echo "  Promoted. Watching rollout..."
    kubectl argo rollouts status "${target}" -n "${NAMESPACE}"
    ;;

  abort)
    : "${target:?Usage: promote.sh abort <service-name>}"
    echo "→ Aborting rollout: ${target} in ${NAMESPACE}"
    kubectl argo rollouts abort "${target}" -n "${NAMESPACE}"
    echo "  Aborted. Rollback in progress..."
    kubectl argo rollouts status "${target}" -n "${NAMESPACE}"
    ;;

  production)
    echo "→ Syncing ArgoCD production app (${ARGOCD_APP})..."
    argocd app sync "${ARGOCD_APP}" \
      --prune \
      --timeout 300
    echo "  Waiting for healthy state..."
    argocd app wait "${ARGOCD_APP}" \
      --health \
      --timeout 300
    echo "  Production sync complete."
    ;;

  *)
    echo "Usage:"
    echo "  promote.sh rollout <service>    # promote a paused canary/bg rollout"
    echo "  promote.sh abort <service>      # abort and roll back a canary"
    echo "  promote.sh production           # sync ArgoCD production app"
    exit 1
    ;;
esac
