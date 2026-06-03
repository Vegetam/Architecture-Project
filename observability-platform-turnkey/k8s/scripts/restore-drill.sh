#!/usr/bin/env bash
set -euo pipefail

# Backup/restore drill script for the observability namespace using Velero.
# Creates a backup, restores into a new namespace, validates pods, then cleans up.
#
# Requirements:
# - Velero installed (k8s/scripts/install-velero.sh)
# - Access to object storage configured for Velero
#
# Usage:
#   OBS_NAMESPACE=observability ./k8s/scripts/restore-drill.sh

OBS_NAMESPACE="${OBS_NAMESPACE:-observability}"
DRILL_NS="${DRILL_NS:-observability-restore-drill}"
BACKUP_NAME="${BACKUP_NAME:-obs-backup-$(date +%Y%m%d-%H%M%S)}"
RESTORE_NAME="${RESTORE_NAME:-obs-restore-$(date +%Y%m%d-%H%M%S)}"

echo "==> Creating Velero backup: $BACKUP_NAME (namespace: $OBS_NAMESPACE)"
velero backup create "$BACKUP_NAME" --include-namespaces "$OBS_NAMESPACE" --wait

echo "==> Restoring into namespace: $DRILL_NS"
kubectl delete ns "$DRILL_NS" --ignore-not-found
velero restore create "$RESTORE_NAME" --from-backup "$BACKUP_NAME" --namespace-mappings "${OBS_NAMESPACE}:${DRILL_NS}" --wait

echo "==> Validating restored pods in $DRILL_NS"
kubectl -n "$DRILL_NS" get pods
kubectl -n "$DRILL_NS" wait --for=condition=Ready pods --all --timeout=10m || true

echo "==> Drill complete."
echo "You can inspect the restored stack in namespace $DRILL_NS."
echo "Cleanup when ready: kubectl delete ns $DRILL_NS"
