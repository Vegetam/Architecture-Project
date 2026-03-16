variable "prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "retention_days" { type = number, default = 30 }

# Workload Identity (recommended)
variable "create_workload_identity" { type = bool, default = true }
variable "aks_oidc_issuer_url" { type = string, default = "" }
variable "namespace" { type = string, default = "observability" }
variable "service_accounts" {
  type    = list(string)
  default = ["loki", "tempo", "observability-prometheus", "velero"]
}
