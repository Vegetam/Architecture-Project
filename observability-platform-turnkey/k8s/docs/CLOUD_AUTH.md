# Cloud-native authentication (no static keys)

This repo supports **cloud-native identity** for object storage and backups:

- **AWS EKS**: IRSA (IAM Roles for Service Accounts)
- **GCP GKE**: Workload Identity
- **Azure AKS**: Workload Identity (federated token)

> Why this matters: you avoid long-lived access keys and rely on short-lived tokens.

It also supports **cloud profiles** so you can add managed-cluster defaults (storage class + topology spread) automatically.

## One-command installs

These wrappers select the provider, enable cloud-native auth, set the matching cloud profile, and default to `PROFILE=medium`.

```bash
./k8s/scripts/install-eks.sh
./k8s/scripts/install-gke.sh
./k8s/scripts/install-aks.sh
```

Override the size if needed:

```bash
PROFILE=large ./k8s/scripts/install-eks.sh
```

---

## AWS (EKS) — IRSA

### Prerequisites
- EKS cluster with **OIDC provider enabled**
- You know:
  - `oidc_provider_arn`
  - `oidc_provider_url`

### Terraform (buckets + lifecycle + IRSA role)

```bash
cd k8s/infra/aws
export TF_VAR_prefix=myteam
export TF_VAR_region=eu-central-1

export TF_VAR_oidc_provider_arn="arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"
export TF_VAR_oidc_provider_url="https://oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"

terraform init
terraform apply
```

### Install
Set env vars from Terraform outputs:
- `AWS_IRSA_ROLE_ARN` (from `irsa_role_arn`)
- `LOKI_S3_BUCKET_*`, `TEMPO_S3_BUCKET`, `VELERO_BUCKET`

Then either use the wrapper:
```bash
./k8s/scripts/install-eks.sh
```

Or the explicit form:
```bash
PROVIDER=aws AUTH_MODE=cloud CLOUD_PROFILE=eks PROFILE=medium ./k8s/scripts/install-observability.sh
PROVIDER=aws AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
```

---

## GCP (GKE) — Workload Identity

### Prerequisites
- GKE cluster with **Workload Identity enabled**

### Terraform (buckets + lifecycle + Workload Identity bindings)

```bash
cd k8s/infra/gcp
export TF_VAR_project_id=my-gcp-project
export TF_VAR_prefix=myteam
export TF_VAR_location=EU

terraform init
terraform apply
```

### Install
Set env vars from Terraform outputs:
- `GCP_GSA_EMAIL` (from `gsa_email`)
- `LOKI_GCS_BUCKET`, `TEMPO_GCS_BUCKET`, `VELERO_BUCKET`

Then either use the wrapper:
```bash
./k8s/scripts/install-gke.sh
```

Or the explicit form:
```bash
PROVIDER=gcp AUTH_MODE=cloud CLOUD_PROFILE=gke PROFILE=medium ./k8s/scripts/install-observability.sh
PROVIDER=gcp AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
```

---

## Azure (AKS) — Workload Identity (federated token)

### Prerequisites
- AKS cluster with **OIDC issuer** + **Workload Identity** enabled
- You know the cluster **OIDC issuer URL**

### Terraform (storage + lifecycle + managed identity + federated credentials)

```bash
cd k8s/infra/azure
export TF_VAR_prefix=myteam
export TF_VAR_resource_group_name=my-rg
export TF_VAR_location=westeurope
export TF_VAR_aks_oidc_issuer_url="https://.../"

terraform init
terraform apply
```

### Install
Set env vars from Terraform outputs:
- `AZURE_CLIENT_ID` (from `azure_client_id`)
- `AZURE_STORAGE_ACCOUNT` + container vars
- `VELERO_BUCKET`

Then either use the wrapper:
```bash
./k8s/scripts/install-aks.sh
```

Or the explicit form:
```bash
PROVIDER=azure AUTH_MODE=cloud CLOUD_PROFILE=aks PROFILE=medium ./k8s/scripts/install-observability.sh
PROVIDER=azure AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
```

### Pod label requirement (Fail Close)
Azure Workload Identity requires the pod label:
- `azure.workload.identity/use: "true"`

The cloud overlays in this repo set that label automatically.

---

## Notes about metrics long-term storage (Thanos)

This stack includes optional Thanos sidecar support via kube-prometheus-stack.

- **AWS S3** + **GCP GCS** work well with IRSA / Workload Identity (no static keys).
- **Azure Blob** support for secretless Thanos is not universally available yet; consider using:
  - managed Prometheus on Azure, or
  - a different long-term metrics backend.
