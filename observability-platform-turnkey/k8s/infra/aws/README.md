# AWS (EKS) object storage + lifecycle + IRSA (Terraform example)

This module provisions:
- S3 buckets for **Loki**, **Tempo**, and optional **Thanos**
- Lifecycle policies for retention (default 30 days; configurable)
- Optional versioning
- **Optional IRSA role** (IAM Roles for Service Accounts) with the required S3 permissions

## How to use (recommended path: IRSA)

1) Ensure your EKS cluster has an OIDC provider enabled.
2) Export variables and apply:

```bash
export TF_VAR_prefix=myteam
export TF_VAR_region=eu-central-1

# From your cluster / IaC (EKS module typically outputs these):
export TF_VAR_oidc_provider_arn="arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"
export TF_VAR_oidc_provider_url="https://oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"

terraform init
terraform apply
```

3) Use the outputs:
- Set `AWS_IRSA_ROLE_ARN` to `irsa_role_arn`
- Set the S3 bucket env vars in your deployment (or External Secrets)

## Notes
- This module creates **one shared IRSA role** that can be used by Loki/Tempo/Prometheus(Thanos)/Velero service accounts.
- If you prefer separate roles per component, copy the IRSA block and split `service_accounts` accordingly.
