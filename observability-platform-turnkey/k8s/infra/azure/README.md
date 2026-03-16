# Azure (AKS) blob storage + lifecycle + Workload Identity (Terraform example)

This module provisions:
- An Azure Storage Account + containers for **Loki**, **Tempo**, and optional **Thanos**
- A Storage Management Policy for retention (default 30 days)
- A **User Assigned Managed Identity** + role assignment (**Storage Blob Data Contributor**)
- **Federated identity credentials** for selected Kubernetes ServiceAccounts (KSAs)

## Prerequisites
- An AKS cluster with **OIDC issuer** and **Workload Identity** enabled.
- You need the cluster OIDC issuer URL (AKS exposes it via Azure CLI).

## Usage

```bash
export TF_VAR_prefix=myteam
export TF_VAR_resource_group_name=my-rg
export TF_VAR_location=westeurope

# From AKS:
export TF_VAR_aks_oidc_issuer_url="https://.../"

terraform init
terraform apply
```

Outputs:
- `azure_client_id` → set `AZURE_CLIENT_ID` when installing with `AUTH_MODE=cloud`
- `storage_account_name` / `container_names` → set the Helm env vars

## Notes
- Loki and Tempo support Azure Workload Identity (federated token) in recent versions.
- Thanos Azure backend does **not** universally support Workload Identity yet; consider using managed Prometheus or a different long-term metrics store on Azure.
