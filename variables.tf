# -----------------------------------------------------------------------------
# Variable Definitions
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-logicapp-demo"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "logicappdemo"
}

# Key Vault Secrets
variable "secret_username" {
  description = "Username secret value to store in Key Vault"
  type        = string
  default     = "demouser"
  sensitive   = true
}

variable "secret_password" {
  description = "Password secret value to store in Key Vault"
  type        = string
  default     = "DemoP@ssw0rd123!"
  sensitive   = true
}

# Logic App Configuration
variable "logic_app_sku" {
  description = "SKU for the Logic App Standard App Service Plan. Use I1v2, I2v2, I3v2 for ASEv3 (required when storage key access is disabled by policy)"
  type        = string
  default     = "I1v2"
  validation {
    condition     = contains(["WS1", "WS2", "WS3", "I1v2", "I2v2", "I3v2"], var.logic_app_sku)
    error_message = "Logic App Standard SKU must be WS1, WS2, WS3 (Workflow Service Plan) or I1v2, I2v2, I3v2 (ASEv3 - required for identity-only storage access)."
  }
}

variable "use_existing_ase" {
  description = "Whether to use an existing App Service Environment v3. When true, ASE is not created by this module - it must exist beforehand."
  type        = bool
  default     = true
}

variable "existing_ase_id" {
  description = "Full resource ID of the existing ASEv3. Required when use_existing_ase = true. Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/hostingEnvironments/{ase-name}"
  type        = string
  default     = ""
}

variable "existing_ase_resource_group" {
  description = "Resource group name where the existing ASE is located. Required when use_existing_ase = true."
  type        = string
  default     = ""
}

variable "existing_ase_name" {
  description = "Name of the existing ASEv3. Required when use_existing_ase = true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Project     = "LogicAppManagedIdentity"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Existing Network Configuration
# This module requires existing VNet/subnet setup
# -----------------------------------------------------------------------------

variable "existing_vnet_resource_group_name" {
  description = "Resource group name where the existing VNet is located."
  type        = string
}

variable "existing_vnet_name" {
  description = "Name of the existing VNet."
  type        = string
}

variable "existing_subnet_name" {
  description = "Name of the existing subnet for ASEv3. Must have delegation for Microsoft.Web/hostingEnvironments."
  type        = string
}

variable "existing_subnet_id" {
  description = "Full resource ID of the existing subnet for ASEv3. Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}"
  type        = string
  default     = ""
}

variable "enable_private_endpoints" {
  description = "Whether to create private endpoints for the storage account. Requires VNet integration."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints (can be different from ASE subnet). Required when enable_private_endpoints = true."
  type        = string
  default     = ""
}

variable "existing_private_dns_zone_ids" {
  description = "Map of existing Private DNS Zone IDs for storage services. Required when enable_private_endpoints = true and using existing DNS zones. Keys: blob, file, table, queue"
  type = object({
    blob  = optional(string, "")
    file  = optional(string, "")
    table = optional(string, "")
    queue = optional(string, "")
  })
  default = {
    blob  = ""
    file  = ""
    table = ""
    queue = ""
  }
}

variable "create_private_dns_zones" {
  description = "Whether to create new Private DNS zones for storage private endpoints. Set to false if you want to use existing DNS zones."
  type        = bool
  default     = true
}

# Note: ASE internal mode is configured in the external ASE module/codebase
# This module only deploys Logic Apps to an existing ASE
