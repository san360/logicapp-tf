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

variable "use_asev3" {
  description = "Whether to use App Service Environment v3. Required when Azure Policy disables storage account shared key access."
  type        = bool
  default     = true
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
