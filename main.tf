# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
locals {
  # Generate unique suffix for globally unique names
  unique_suffix = substr(md5(azurerm_resource_group.main.id), 0, 8)

  # Resource names
  storage_account_name  = lower(replace("st${var.project_name}${local.unique_suffix}", "-", ""))
  key_vault_name        = "kv-${var.project_name}-${local.unique_suffix}"
  app_service_plan_name = "asp-${var.project_name}-ase-${var.environment}"
  logic_app_name        = "logic-${var.project_name}-${var.environment}"
  user_identity_name    = "id-${var.project_name}-${var.environment}"

  # Network resource resolution - always use existing network resources
  vnet_id = data.azurerm_virtual_network.existing.id
  subnet_id = var.existing_subnet_id != "" ? var.existing_subnet_id : data.azurerm_subnet.existing.id
  vnet_name = var.existing_vnet_name
  vnet_resource_group = var.existing_vnet_resource_group_name

  # Private endpoint subnet (can be different from ASE subnet)
  private_endpoint_subnet_id = var.private_endpoint_subnet_id != "" ? var.private_endpoint_subnet_id : local.subnet_id

  # Base app settings for Logic App
  base_app_settings = [
    { name = "FUNCTIONS_EXTENSION_VERSION", value = "~4" },
    { name = "FUNCTIONS_WORKER_RUNTIME", value = "dotnet" },
    { name = "FUNCTIONS_INPROC_NET8_ENABLED", value = "1" },
    { name = "AzureWebJobsStorage__managedIdentityResourceId", value = azurerm_user_assigned_identity.logic_app.id },
    { name = "AzureWebJobsStorage__blobServiceUri", value = "https://${local.storage_account_name}.blob.core.windows.net" },
    { name = "AzureWebJobsStorage__queueServiceUri", value = "https://${local.storage_account_name}.queue.core.windows.net" },
    { name = "AzureWebJobsStorage__tableServiceUri", value = "https://${local.storage_account_name}.table.core.windows.net" },
    { name = "AzureWebJobsStorage__credential", value = "managedidentity" },
    { name = "APP_KIND", value = "workflowApp" }
  ]

  # VNet integration app settings (required for private endpoints)
  vnet_app_settings = var.enable_private_endpoints ? [
    { name = "WEBSITE_CONTENTOVERVNET", value = "1" },
    { name = "WEBSITE_VNET_ROUTE_ALL", value = "1" }
  ] : []

  # Combined app settings
  logic_app_settings = concat(local.base_app_settings, local.vnet_app_settings)
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
# Data Sources for Existing Network Resources
# This module requires existing VNet/subnet setup
# -----------------------------------------------------------------------------
data "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_vnet_resource_group_name
}

data "azurerm_subnet" "existing" {
  name                 = var.existing_subnet_name
  virtual_network_name = var.existing_vnet_name
  resource_group_name  = var.existing_vnet_resource_group_name
}

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

resource "azurerm_role_assignment" "deployer_storage_blob" {
  scope                = azapi_resource.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
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
# App Service Plan on existing ASEv3
# ASEv3 is managed externally - this module only deploys Logic Apps
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "logic_app" {
  name                         = local.app_service_plan_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  os_type                      = "Windows"
  sku_name                     = var.logic_app_sku
  app_service_environment_id   = var.existing_ase_id

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
        netFrameworkVersion  = "v8.0"
        nodeVersion          = "~20"
        appSettings = concat(local.logic_app_settings, [
          { name = "KEY_VAULT_URL", value = azurerm_key_vault.main.vault_uri }
        ])
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
# Private DNS Zones for Storage Account (created only when enabled and not using existing)
# Required for private endpoint DNS resolution
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "storage_blob" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_file" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_table" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_queue" {
  count               = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Private DNS Zone VNet Links (link DNS zones to VNet for resolution)
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                  = "link-blob-${var.project_name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_file" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                  = "link-file-${var.project_name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_file[0].name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_table" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                  = "link-table-${var.project_name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_table[0].name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_queue" {
  count                 = var.enable_private_endpoints && var.create_private_dns_zones ? 1 : 0
  name                  = "link-queue-${var.project_name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_queue[0].name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# -----------------------------------------------------------------------------
# Local values for Private DNS Zone IDs (use existing or created)
# -----------------------------------------------------------------------------
locals {
  private_dns_zone_ids = {
    blob = var.enable_private_endpoints ? (
      var.create_private_dns_zones ? azurerm_private_dns_zone.storage_blob[0].id : var.existing_private_dns_zone_ids.blob
    ) : ""
    file = var.enable_private_endpoints ? (
      var.create_private_dns_zones ? azurerm_private_dns_zone.storage_file[0].id : var.existing_private_dns_zone_ids.file
    ) : ""
    table = var.enable_private_endpoints ? (
      var.create_private_dns_zones ? azurerm_private_dns_zone.storage_table[0].id : var.existing_private_dns_zone_ids.table
    ) : ""
    queue = var.enable_private_endpoints ? (
      var.create_private_dns_zones ? azurerm_private_dns_zone.storage_queue[0].id : var.existing_private_dns_zone_ids.queue
    ) : ""
  }
}

# -----------------------------------------------------------------------------
# Private Endpoints for Storage Account
# Required when storage account needs private network access
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.storage_account_name}-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = local.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-blob"
    private_connection_resource_id = azapi_resource.storage_account.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_ids.blob]
  }
}

resource "azurerm_private_endpoint" "storage_file" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.storage_account_name}-file"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = local.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-file"
    private_connection_resource_id = azapi_resource.storage_account.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_ids.file]
  }
}

resource "azurerm_private_endpoint" "storage_table" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.storage_account_name}-table"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = local.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-table"
    private_connection_resource_id = azapi_resource.storage_account.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_ids.table]
  }
}

resource "azurerm_private_endpoint" "storage_queue" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.storage_account_name}-queue"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = local.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-queue"
    private_connection_resource_id = azapi_resource.storage_account.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_ids.queue]
  }
}

