# Velero configuration (backup/restore)

This folder contains Helm values for Velero.

## Providers

Pick a provider overlay (static-key compatible):
- `velero-minio.yaml` (S3-compatible: MinIO/dev)
- `velero-aws.yaml`
- `velero-gcp.yaml`
- `velero-azure.yaml`

Cloud-native identity overlays (recommended):
- `velero-aws-irsa.yaml` (AWS IRSA)
- `velero-gcp-wi.yaml` (GKE Workload Identity)
- `velero-azure-wi.yaml` (AKS Workload Identity)

## Install

```bash
# dev/local
PROVIDER=minio ./k8s/scripts/install-velero.sh

# cloud-native identity
PROVIDER=aws AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
PROVIDER=gcp AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
PROVIDER=azure AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
```

Credentials:
- Prefer External Secrets / workload identity.
- If using a static credentials secret, create it in the `velero` namespace.
