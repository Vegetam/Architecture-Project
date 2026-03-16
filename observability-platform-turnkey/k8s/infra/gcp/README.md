# GCP (GKE) object storage + lifecycle + Workload Identity (Terraform example)

This module provisions:
- GCS buckets for **Loki**, **Tempo**, and optional **Thanos**
- Bucket lifecycle rules for retention (default 30 days; configurable)
- A shared **Google Service Account (GSA)** for object storage access
- Workload Identity bindings so selected Kubernetes ServiceAccounts (KSAs) can impersonate the GSA

## Usage

```bash
export TF_VAR_project_id=my-gcp-project
export TF_VAR_prefix=myteam
export TF_VAR_location=EU

terraform init
terraform apply
```

Outputs:
- `gsa_email` → set `GCP_GSA_EMAIL` for installs that use `AUTH_MODE=cloud`
- `bucket_names` → set `LOKI_GCS_BUCKET`, `TEMPO_GCS_BUCKET`, etc.

## Notes
- This module assumes Workload Identity is enabled on your GKE cluster.
- The default KSA names used by this repo are: `loki`, `tempo`, `observability-prometheus`, `velero`.
