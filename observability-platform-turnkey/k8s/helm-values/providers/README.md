# Provider overlays (hybrid)

These files let you switch the stack between:

- **MinIO (dev/local)** and
- **S3 / GCS / Azure Blob (production)**

They are designed to be used with `k8s/scripts/install-observability.sh`.

## Auth modes

For cloud providers you can choose:

- `AUTH_MODE=static` (default): use access keys (via External Secrets or K8s Secrets)
- `AUTH_MODE=cloud`: use **cloud-native identity** (recommended)
  - AWS: **IRSA**
  - GCP: **Workload Identity**
  - Azure: **Workload Identity (federated token)**

Cloud-native overlays:
- `loki-aws-irsa.yaml`, `tempo-aws-irsa.yaml`
- `loki-gcp-wi.yaml`, `tempo-gcp-wi.yaml`
- `loki-azure-wi.yaml`, `tempo-azure-wi.yaml`

> Notes:
> - For production cloud environments, prefer **workload identity / IRSA** over static keys.
> - If you must use static keys, store them via External Secrets (recommended) or Kubernetes Secrets.


## Canonical provider filenames

The install scripts use `PROVIDER=aws|gcp|azure|minio` and expect these files:

- `loki-aws.yaml`, `tempo-aws.yaml` (static keys)
- `loki-gcp.yaml`, `tempo-gcp.yaml` (static keys)
- `loki-azure.yaml`, `tempo-azure.yaml` (static keys)
- `loki-minio.yaml`, `tempo-minio.yaml` (dev)

(Older aliases like `loki-s3.yaml` / `loki-gcs.yaml` are kept for reference.)
