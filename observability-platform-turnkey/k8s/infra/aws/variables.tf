variable "prefix" { type = string }
variable "region" { type = string }
variable "retention_days" { type = number, default = 30 }
variable "enable_versioning" { type = bool, default = false }

# IRSA (optional but recommended)
variable "create_irsa_role" { type = bool, default = true }
variable "oidc_provider_arn" { type = string, default = "" }
variable "oidc_provider_url" { type = string, default = "" }
variable "namespace" { type = string, default = "observability" }

# ServiceAccounts that should be allowed to assume the IRSA role.
# These names should match the Helm values (this repo uses loki/tempo by default).
variable "service_accounts" {
  type    = list(string)
  default = ["loki", "tempo", "observability-prometheus", "velero"]
}

variable "irsa_role_name" { type = string, default = "" }
