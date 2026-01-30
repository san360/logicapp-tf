# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
locals {
  # Generate unique suffix for globally unique names
  unique_suffix = substr(md5(azurerm_resource_group.main.id), 0, 8)

  # Resource names
  storage_account_name  = lower(replace("st${var.project_name}${local.unique_suffix}", "-", ""))
  key_vault_name        = "kv-${var.project_name}-${local.unique_suffix}"
  # Use different name for ASEv3 App Service Plan to avoid conflicts
  app_service_plan_name = var.use_asev3 ? "asp-${var.project_name}-ase-${var.environment}" : "asp-${var.project_name}-${var.environment}"
  logic_app_name        = "logic-${var.project_name}-${var.environment}"
  user_identity_name    = "id-${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = merge(var.tags, { SecurityControl = "Ignore" })
}

# -----------------------------------------------------------------------------
# Get Current Azure Client Configuration
# -----------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# User-Assigned Managed Identity for Logic App Storage Access
# Per Microsoft docs for identity-based storage access
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "logic_app" {
  name                = local.user_identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Storage Account using AzAPI (identity-only, no shared keys)
# This configuration requires ASEv3 hosting for Logic App Standard
# Azure Policy requires allowSharedKeyAccess = false
# -----------------------------------------------------------------------------
resource "azapi_resource" "storage_account" {
  type      = "Microsoft.Storage/storageAccounts@2023-01-01"
  name      = local.storage_account_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  tags      = merge(var.tags, { SecurityControl = "Ignore" })

  body = jsonencode({
    kind = "StorageV2"
    sku = {
      name = "Standard_LRS"
    }
    properties = {
      minimumTlsVersion             = "TLS1_2"
      allowBlobPublicAccess         = false
      allowSharedKeyAccess          = false
      defaultToOAuthAuthentication  = true
      supportsHttpsTrafficOnly      = true
    }
  })

  response_export_values = ["properties.primaryEndpoints", "id"]
}

# -----------------------------------------------------------------------------
# Storage Account Role Assignments for User-Assigned Managed Identity
# Required roles per Microsoft docs for identity-based storage access
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "ua_storage_account_contributor" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

resource "azurerm_role_assignment" "ua_storage_blob_data_owner" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

resource "azurerm_role_assignment" "ua_storage_queue_data_contributor" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

resource "azurerm_role_assignment" "ua_storage_table_data_contributor" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

# Required for ASEv3 file share access with identity-based auth
resource "azurerm_role_assignment" "ua_storage_file_data_privileged" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

# Role assignment for current deployer to access storage for file share creation
resource "azurerm_role_assignment" "deployer_storage_contributor" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_storage_file" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enable_rbac_authorization  = true

  tags = var.tags
}

# Grant current user/service principal access to Key Vault
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -----------------------------------------------------------------------------
# Key Vault Secrets
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "username" {
  name         = "demo-username"
  value        = var.secret_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "password" {
  name         = "demo-password"
  value        = var.secret_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

# -----------------------------------------------------------------------------
# Virtual Network for ASEv3 (required when using identity-only storage access)
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "ase" {
  count               = var.use_asev3 ? 1 : 0
  name                = "vnet-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = merge(var.tags, { SecurityControl = "Ignore" })
}

# Dedicated subnet for ASEv3 (requires /24 or larger)
resource "azurerm_subnet" "ase" {
  count                = var.use_asev3 ? 1 : 0
  name                 = "snet-ase"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.ase[0].name
  address_prefixes     = ["10.0.0.0/24"]

  delegation {
    name = "Microsoft.Web.hostingEnvironments"
    service_delegation {
      name    = "Microsoft.Web/hostingEnvironments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# -----------------------------------------------------------------------------
# App Service Environment v3 (ASEv3) - Required for identity-only storage
# Per Microsoft docs: Only ASEv3 supports disabling storage account shared keys
# Using external mode for Azure Portal access to Logic Apps
# -----------------------------------------------------------------------------
resource "azurerm_app_service_environment_v3" "main" {
  count                        = var.use_asev3 ? 1 : 0
  name                         = "ase-${var.project_name}-${var.environment}"
  resource_group_name          = azurerm_resource_group.main.name
  subnet_id                    = azurerm_subnet.ase[0].id
  internal_load_balancing_mode = "None"
  
  tags = merge(var.tags, { SecurityControl = "Ignore" })
}

# -----------------------------------------------------------------------------
# App Service Plan (ASEv3 or WorkflowStandard SKU)
# ASEv3 required when Azure Policy disables storage shared key access
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "logic_app" {
  name                         = local.app_service_plan_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  os_type                      = "Windows"
  sku_name                     = var.logic_app_sku
  app_service_environment_id   = var.use_asev3 ? azurerm_app_service_environment_v3.main[0].id : null

  tags = merge(var.tags, { SecurityControl = "Ignore" })
}

# -----------------------------------------------------------------------------
# Logic App Standard using AzAPI (identity-based storage access)
# Uses User-Assigned Managed Identity for storage access (no shared keys)
# This configuration is supported only with ASEv3 hosting
# -----------------------------------------------------------------------------
resource "azapi_resource" "logic_app" {
  type      = "Microsoft.Web/sites@2023-01-01"
  name      = local.logic_app_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  tags      = merge(var.tags, { SecurityControl = "Ignore" })

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app.id]
  }

  body = jsonencode({
    kind = "functionapp,workflowapp"
    properties = {
      serverFarmId = azurerm_service_plan.logic_app.id
      httpsOnly    = true
      siteConfig = {
        netFrameworkVersion  = "v6.0"
        appSettings = [
          { name = "FUNCTIONS_EXTENSION_VERSION", value = "~4" },
          { name = "FUNCTIONS_WORKER_RUNTIME", value = "dotnet" },
          { name = "AzureWebJobsStorage__managedIdentityResourceId", value = azurerm_user_assigned_identity.logic_app.id },
          { name = "AzureWebJobsStorage__blobServiceUri", value = "https://${local.storage_account_name}.blob.core.windows.net" },
          { name = "AzureWebJobsStorage__queueServiceUri", value = "https://${local.storage_account_name}.queue.core.windows.net" },
          { name = "AzureWebJobsStorage__tableServiceUri", value = "https://${local.storage_account_name}.table.core.windows.net" },
          { name = "AzureWebJobsStorage__credential", value = "managedidentity" },
          { name = "KV_SECRET_USERNAME", value = "@Microsoft.KeyVault(VaultName=${local.key_vault_name};SecretName=demo-username)" },
          { name = "KV_SECRET_PASSWORD", value = "@Microsoft.KeyVault(VaultName=${local.key_vault_name};SecretName=demo-password)" },
          { name = "KEY_VAULT_URL", value = azurerm_key_vault.main.vault_uri },
          { name = "APP_KIND", value = "workflowApp" }
        ]
        use32BitWorkerProcess = false
        ftpsState            = "FtpsOnly"
        minTlsVersion        = "1.2"
        alwaysOn             = true
      }
    }
  })

  depends_on = [
    azapi_resource.storage_account,
    azurerm_role_assignment.ua_storage_account_contributor,
    azurerm_role_assignment.ua_storage_blob_data_owner,
    azurerm_role_assignment.ua_storage_queue_data_contributor,
    azurerm_role_assignment.ua_storage_table_data_contributor,
    azurerm_key_vault_secret.username,
    azurerm_key_vault_secret.password
  ]

  response_export_values = ["properties.defaultHostName", "identity.principalId"]
}

# -----------------------------------------------------------------------------
# Key Vault Access for Logic App System-Assigned Managed Identity
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "logic_app_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = jsondecode(azapi_resource.logic_app.output).identity.principalId
}

# -----------------------------------------------------------------------------
# Archive Logic App Source Files for ZIP Deployment
# -----------------------------------------------------------------------------
data "archive_file" "logic_app_package" {
  type        = "zip"
  output_path = "${path.module}/logic-app-package.zip"
  source_dir  = "${path.module}/logic-app-src"

  excludes = [
    "workflow-designtime",
    "workflow-designtime/*",
    "local.settings.json",
    ".vscode",
    ".vscode/*"
  ]
}

# -----------------------------------------------------------------------------
# Deploy Logic App using Azure CLI (ZIP Deploy)
# -----------------------------------------------------------------------------
resource "null_resource" "logic_app_deploy" {
  triggers = {
    package_md5 = data.archive_file.logic_app_package.output_md5
  }

  provisioner "local-exec" {
    command = <<-EOT
      az logicapp deployment source config-zip \
        --name ${local.logic_app_name} \
        --resource-group ${azurerm_resource_group.main.name} \
        --src ${data.archive_file.logic_app_package.output_path}
    EOT
  }

  depends_on = [
    azapi_resource.logic_app,
    data.archive_file.logic_app_package,
    azurerm_role_assignment.logic_app_kv_secrets
  ]
}
