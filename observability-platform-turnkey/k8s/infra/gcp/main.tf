terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 5.0" }
  }
}

provider "google" {
  project = var.project_id
}

locals {
  buckets = {
    loki   = "${var.prefix}-loki"
    tempo  = "${var.prefix}-tempo"
    thanos = "${var.prefix}-thanos"
  }
}

resource "google_storage_bucket" "b" {
  for_each      = local.buckets
  name          = each.value
  location      = var.location
  force_destroy = false

  lifecycle_rule {
    action { type = "Delete" }
    condition { age = var.retention_days }
  }
}

# Shared GSA for object storage access (recommended)
resource "google_service_account" "objstore" {
  account_id   = replace("${var.prefix}-obs-objstore", "_", "-")
  display_name = "Observability object storage"
}

# Grant the GSA permissions on the buckets
resource "google_storage_bucket_iam_member" "bucket_admin" {
  for_each = google_storage_bucket.b
  bucket   = each.value.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.objstore.email}"
}

# Allow selected KSAs to impersonate the GSA (Workload Identity)
resource "google_service_account_iam_member" "wi" {
  for_each           = toset(var.service_accounts)
  service_account_id = google_service_account.objstore.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${each.value}]"
}

output "bucket_names" {
  value = local.buckets
}

output "gsa_email" {
  value       = google_service_account.objstore.email
  description = "Google Service Account email for Workload Identity (set GCP_GSA_EMAIL)."
}
