# Implementation Details - Azure Logic App Standard with ASEv3 and Identity-Based Storage

## Document Version
- **Date**: January 30, 2026
- **Version**: 2.0.0

---

## 1. Overview

This implementation creates an Azure Logic App (Standard) hosted on **App Service Environment v3 (ASEv3)** that:
1. Uses **User-Assigned Managed Identity** for storage account access (no shared keys)
2. Uses **System-Assigned Managed Identity** for Key Vault secret access
3. Accesses **Azure Key Vault** to fetch secrets without storing credentials in code
4. Calls **httpbin.org** GET endpoint with query string parameters
5. Deploys via **Terraform** with AzAPI provider for advanced configurations

---

## 2. Why ASEv3 is Required

### Azure Policy Constraint

When Azure Policy enforces `allowSharedKeyAccess = false` on storage accounts, only **ASEv3** supports identity-based storage authentication for Logic App Standard.

**Microsoft Documentation Quote:**
> "Currently, you can't disable storage account key access for Standard logic apps that use the Workflow Service Plan hosting option. However, if your logic app uses the App Service Environment v3 hosting option, you can disable storage account key access."

### Hosting Options Comparison

| Hosting Option | Identity-Only Storage | Shared Key Required | Use Case |
|---------------|----------------------|---------------------|----------|
| Workflow Service Plan (WS1/WS2/WS3) | ❌ | ✅ | Standard deployments |
| **App Service Environment v3** | ✅ | ❌ | Policy-compliant deployments |

---

## 3. Architecture Components

### 3.1 Resource Group
- **Name**: `rg-logicapp-tf`
- **Tag**: `SecurityControl = Ignore` (required for policy compliance)
- Contains all related resources

### 3.2 Virtual Network
- **Address Space**: `10.0.0.0/16`
- **Purpose**: Required for ASEv3 deployment

### 3.3 Subnet
- **Address Prefix**: `10.0.0.0/24`
- **Delegation**: `Microsoft.Web/hostingEnvironments`
- **Purpose**: Dedicated subnet for ASEv3 (requires /24 or larger)

### 3.4 App Service Environment v3
- **Mode**: External (`internal_load_balancing_mode = "None"`)
- **Purpose**: Enables identity-only storage authentication
- **External Mode Benefits**: Allows Azure Portal access to Logic App workflows

### 3.5 Storage Account (AzAPI Resource)
- **Configuration**:
  ```hcl
  allowSharedKeyAccess          = false
  defaultToOAuthAuthentication  = true
  ```
- **SKU**: Standard LRS
- **TLS**: Minimum 1.2
- **Purpose**: Backend storage for Logic App (queues, blobs, tables)

### 3.6 User-Assigned Managed Identity
- **Purpose**: Storage account access
- **Roles Assigned**:
  - Storage Account Contributor
  - Storage Blob Data Owner
  - Storage Queue Data Contributor
  - Storage Table Data Contributor
  - Storage File Data Privileged Contributor

### 3.7 Key Vault
- **Authorization**: RBAC (recommended over access policies)
- **Secrets**:
  - `demo-username`: Sample username credential
  - `demo-password`: Sample password credential

### 3.8 App Service Plan
- **SKU**: I1v2 (Isolated v2 for ASEv3)
- **OS Type**: Windows (required for Logic App Standard)

### 3.9 Logic App Standard (AzAPI Resource)
- **Kind**: `functionapp,workflowapp`
- **Identities**:
  - System-Assigned (for Key Vault access)
  - User-Assigned (for Storage access)

---

## 4. Security Implementation

### 4.1 Dual Managed Identity Architecture

```hcl
identity {
  type         = "SystemAssigned, UserAssigned"
  identity_ids = [azurerm_user_assigned_identity.logic_app.id]
}
```

**Why Two Identities?**
- **User-Assigned**: For storage access - allows pre-creation and role assignment before Logic App deployment
- **System-Assigned**: For Key Vault access - simpler lifecycle management

### 4.2 Storage Account Access (User-Assigned Identity)

Required role assignments per Microsoft documentation:

| Role | Purpose |
|------|---------|
| Storage Account Contributor | Manage storage account |
| Storage Blob Data Owner | Full blob access |
| Storage Queue Data Contributor | Queue operations (workflow state) |
| Storage Table Data Contributor | Table operations |
| Storage File Data Privileged Contributor | File share access (ASEv3 requirement) |

### 4.3 Key Vault Access (System-Assigned Identity)

```hcl
resource "azurerm_role_assignment" "logic_app_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = jsondecode(azapi_resource.logic_app.output).identity.principalId
}
```

### 4.4 Identity-Based Storage App Settings

Per Microsoft documentation, the correct settings are:

```hcl
app_settings = [
  { name = "AzureWebJobsStorage__managedIdentityResourceId", value = "<user-assigned-identity-resource-id>" },
  { name = "AzureWebJobsStorage__blobServiceUri", value = "https://<storage>.blob.core.windows.net" },
  { name = "AzureWebJobsStorage__queueServiceUri", value = "https://<storage>.queue.core.windows.net" },
  { name = "AzureWebJobsStorage__tableServiceUri", value = "https://<storage>.table.core.windows.net" },
  { name = "AzureWebJobsStorage__credential", value = "managedidentity" }
]
```

**Important**: Do NOT include `AzureWebJobsStorage` connection string - this must be removed/absent for identity-based auth to work.

---

## 5. Terraform Provider Configuration

### 5.1 Required Providers

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.117.1"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.15.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
  }
}
```

### 5.2 Why AzAPI Provider?

The `azurerm` provider's `azurerm_logic_app_standard` resource doesn't support:
- `allowSharedKeyAccess = false` on storage accounts
- Complex app settings array format required for identity-based storage
- Flexible identity configuration

The `azapi` provider allows direct ARM API calls with full configuration control.

---

## 6. Workflow Implementation

### 6.1 Workflow Structure

```
logic-app-src/
├── host.json              # Runtime configuration
├── connections.json       # Connection definitions
├── local.settings.json    # Local development (not deployed)
└── httpbin-workflow/
    └── workflow.json      # Workflow definition
```

### 6.2 Accessing Key Vault Secrets in Workflow

```json
{
  "type": "InitializeVariable",
  "inputs": {
    "variables": [{
      "name": "username",
      "type": "string",
      "value": "@appsetting('KV_SECRET_USERNAME')"
    }]
  }
}
```

The `@appsetting()` function retrieves the app setting value, which is automatically resolved from Key Vault by the platform.

---

## 7. Terraform Resource Dependencies

```
azurerm_resource_group
    │
    ├── azurerm_virtual_network
    │       └── azurerm_subnet (ASE delegation)
    │               └── azurerm_app_service_environment_v3
    │                       └── azurerm_service_plan (I1v2)
    │
    ├── azurerm_user_assigned_identity
    │       └── azurerm_role_assignment (storage roles x5)
    │
    ├── azapi_resource (storage_account)
    │       └── azurerm_role_assignment (deployer roles)
    │
    ├── azurerm_key_vault
    │       ├── azurerm_role_assignment (admin)
    │       ├── azurerm_key_vault_secret (username)
    │       └── azurerm_key_vault_secret (password)
    │
    └── azapi_resource (logic_app)
            └── azurerm_role_assignment (KV Secrets User)
                    └── null_resource (ZIP deploy)
```

---

## 8. Deployment Timeline

| Phase | Resource | Approximate Time |
|-------|----------|-----------------|
| 1 | Resource Group, VNet, Subnet, Identities | ~1 minute |
| 2 | ASEv3 | **~10-15 minutes** |
| 3 | App Service Plan | **~15-20 minutes** |
| 4 | Storage Account, Key Vault, Secrets | ~1 minute |
| 5 | Role Assignments | ~2 minutes |
| 6 | Logic App | ~1 minute |
| 7 | ZIP Deployment | ~1 minute |
| **Total** | | **~30-40 minutes** |

---

## 9. Troubleshooting Guide

### 9.1 Storage Authentication Errors

**Error**: `Microsoft.WindowsAzure.Storage: Value cannot be null. (Parameter 'connectionString')`

**Causes & Solutions**:
1. Missing `AzureWebJobsStorage__credential` app setting
2. Wrong value - must be `managedidentity` (lowercase)
3. `AzureWebJobsStorage` connection string still present (must be removed)
4. Missing role assignments on storage account

### 9.2 Credential Type Error

**Error**: `The authentication credential type for the storage account isn't valid`

**Solution**: Use these exact app settings:
```
AzureWebJobsStorage__managedIdentityResourceId = <full-resource-id>
AzureWebJobsStorage__credential = managedidentity
```

### 9.3 ASEv3 Portal Access Issues

**Symptom**: Cannot access Logic App workflows from Azure Portal

**Cause**: ASEv3 deployed with internal load balancing

**Solution**: Set `internal_load_balancing_mode = "None"` for external access

---

## 10. Cost Estimation

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|----------------------|
| ASEv3 Stamp Fee | - | ~$1,000+ |
| App Service Plan | I1v2 | ~$300 |
| Key Vault | Standard | ~$0.03/10k operations |
| Storage Account | Standard LRS | ~$2-5 |
| **Total** | | **~$1,300+/month** |

**Note**: ASEv3 has significant base costs. Consider this for production workloads requiring policy compliance.

---

## 11. Production Considerations

### Security Enhancements
- [ ] Configure NSG rules for ASEv3 subnet
- [ ] Enable diagnostic logging to Log Analytics
- [ ] Implement Azure Front Door for public endpoints
- [ ] Enable Private Link for Key Vault

### Reliability Enhancements
- [ ] Configure deployment slots for zero-downtime deployments
- [ ] Enable geo-redundant storage
- [ ] Set up Azure Monitor alerts
- [ ] Implement retry policies in workflow

### Performance Enhancements
- [ ] Scale up to I2v2/I3v2 for higher throughput
- [ ] Enable Application Insights
- [ ] Optimize workflow with parallel actions

---

## 12. References

1. [Logic App Standard - Identity-based Storage](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account)
2. [App Service Environment v3 Overview](https://learn.microsoft.com/en-us/azure/app-service/environment/overview)
3. [Managed Identity in Logic Apps](https://learn.microsoft.com/en-us/azure/logic-apps/authenticate-with-managed-identity)
4. [Key Vault References for App Service](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
5. [AzAPI Terraform Provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
