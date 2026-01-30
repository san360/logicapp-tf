# -----------------------------------------------------------------------------
# Output Values
# -----------------------------------------------------------------------------

locals {
  logic_app_output = jsondecode(azapi_resource.logic_app.output)
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azapi_resource.logic_app.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App"
  value       = azapi_resource.logic_app.id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = local.logic_app_output.properties.defaultHostName
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic App's System-Assigned Managed Identity"
  value       = local.logic_app_output.identity.principalId
}

output "logic_app_managed_identity_tenant_id" {
  description = "Tenant ID of the Logic App's System-Assigned Managed Identity"
  value       = data.azurerm_client_config.current.tenant_id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azapi_resource.storage_account.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.logic_app.id
}

output "workflow_designer_url" {
  description = "URL to access the workflow designer in Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azapi_resource.logic_app.id}/logicAppsDesigner"
}

output "workflow_management_url" {
  description = "URL to manage workflows"
  value       = "https://${local.logic_app_output.properties.defaultHostName}"
}
