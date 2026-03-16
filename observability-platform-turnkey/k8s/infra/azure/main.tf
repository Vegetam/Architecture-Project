terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_storage_account" "sa" {
  name                     = replace("${var.prefix}obs", "/[^a-z0-9]/", "")
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

locals {
  containers = {
    loki   = "loki"
    tempo  = "tempo"
    thanos = "thanos"
  }
}

resource "azurerm_storage_container" "c" {
  for_each              = local.containers
  name                  = each.value
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# Lifecycle management policy: delete blobs older than retention_days
resource "azurerm_storage_management_policy" "policy" {
  storage_account_id = azurerm_storage_account.sa.id

  rule {
    name    = "delete-old-blobs"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = [for c in azurerm_storage_container.c : "${c.name}/"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.retention_days
      }
    }
  }
}

# -----------------------------
# Workload Identity (User-Assigned Managed Identity + federated credentials)
# -----------------------------

resource "azurerm_user_assigned_identity" "objstore" {
  count               = var.create_workload_identity ? 1 : 0
  name                = "${var.prefix}-obs-objstore"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Grant the identity access to the Storage Account (Blob Data Contributor)
resource "azurerm_role_assignment" "blob_contributor" {
  count                = var.create_workload_identity ? 1 : 0
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.objstore[0].principal_id
}

# Federated identity credentials for each KSA
resource "azurerm_federated_identity_credential" "ksa" {
  for_each            = var.create_workload_identity && var.aks_oidc_issuer_url != "" ? toset(var.service_accounts) : []
  name                = "${var.prefix}-${each.value}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.objstore[0].id

  issuer    = var.aks_oidc_issuer_url
  subject   = "system:serviceaccount:${var.namespace}:${each.value}"
  audiences = ["api://AzureADTokenExchange"]
}

output "storage_account_name" { value = azurerm_storage_account.sa.name }
output "container_names" { value = local.containers }

output "azure_client_id" {
  value       = var.create_workload_identity ? azurerm_user_assigned_identity.objstore[0].client_id : ""
  description = "Client ID for Azure Workload Identity (set AZURE_CLIENT_ID)."
}
