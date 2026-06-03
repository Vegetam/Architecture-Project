variable "project_id" { type = string }
variable "prefix" { type = string }
variable "location" { type = string, default = "US" }
variable "retention_days" { type = number, default = 30 }

# Workload Identity (recommended)
variable "namespace" { type = string, default = "observability" }
variable "service_accounts" {
  type    = list(string)
  default = ["loki", "tempo", "observability-prometheus", "velero"]
}
