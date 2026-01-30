# Azure Logic App Standard with ASEv3 and Identity-Based Storage - Terraform Deployment

## Overview

This Terraform project deploys an Azure Logic App (Standard) on **App Service Environment v3 (ASEv3)** with:
1. **Identity-based storage authentication** (no shared key access) - compliant with Azure Policy
2. **User-Assigned Managed Identity** for storage access with proper RBAC roles
3. **System-Assigned Managed Identity** for Key Vault secret access
4. Calls httpbin.org GET endpoint with query string parameters
5. Demonstrates secure secret management using Key Vault references

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Azure Resource Group (rg-logicapp-tf)                     │
│                        Tag: SecurityControl = Ignore                             │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                    Virtual Network (10.0.0.0/16)                             ││
│  │                                                                              ││
│  │  ┌────────────────────────────────────────────────────────────────────────┐ ││
│  │  │              ASEv3 Subnet (10.0.0.0/24)                                │ ││
│  │  │              Delegation: Microsoft.Web/hostingEnvironments             │ ││
│  │  │                                                                        │ ││
│  │  │   ┌──────────────────────────────────────────────────────────────────┐│ ││
│  │  │   │    App Service Environment v3 (External Mode)                    ││ ││
│  │  │   │    internal_load_balancing_mode = "None"                         ││ ││
│  │  │   │                                                                  ││ ││
│  │  │   │   ┌─────────────────────┐    ┌─────────────────────────────────┐││ ││
│  │  │   │   │   App Service Plan  │    │   Logic App Standard            │││ ││
│  │  │   │   │   SKU: I1v2         │◄───│   (workflowapp)                 │││ ││
│  │  │   │   │   (Isolated v2)     │    │                                 │││ ││
│  │  │   │   └─────────────────────┘    │   Identities:                   │││ ││
│  │  │   │                              │   - System-Assigned (KV access) │││ ││
│  │  │   │                              │   - User-Assigned (Storage)     │││ ││
│  │  │   │                              └─────────────────────────────────┘││ ││
│  │  │   └──────────────────────────────────────────────────────────────────┘│ ││
│  │  └────────────────────────────────────────────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
│                                                                                  │
│  ┌─────────────────────────────┐       ┌──────────────────────────────────────┐ │
│  │   Azure Key Vault           │       │   Storage Account                    │ │
│  │   (RBAC Authorization)      │       │   allowSharedKeyAccess = false       │ │
│  │                             │       │   (identity-only authentication)     │ │
│  │   Secrets:                  │       │                                      │ │
│  │   - demo-username           │       │   Role Assignments (User Identity):  │ │
│  │   - demo-password           │       │   - Storage Account Contributor      │ │
│  │                             │       │   - Storage Blob Data Owner          │ │
│  │   Role: Key Vault           │       │   - Storage Queue Data Contributor   │ │
│  │   Secrets User              │       │   - Storage Table Data Contributor   │ │
│  │   (System Identity)         │       │   - Storage File Data Privileged     │ │
│  └─────────────────────────────┘       └──────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────┐                                                │
│  │  User-Assigned Identity     │                                                │
│  │  (for storage access)       │                                                │
│  └─────────────────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       │ HTTPS
                                       ▼
                    ┌──────────────────────────────────────┐
                    │         External API                  │
                    │         httpbin.org/get               │
                    └──────────────────────────────────────┘
```

## Why ASEv3?

**Azure Policy Requirement**: When Azure Policy enforces `allowSharedKeyAccess = false` on storage accounts:
- **Workflow Service Plan (WS1/WS2/WS3)** does NOT support identity-only storage authentication
- **App Service Environment v3 (ASEv3)** is the ONLY hosting option that supports disabling storage account shared keys

Per [Microsoft Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account):
> "Currently, you can't disable storage account key access for Standard logic apps that use the Workflow Service Plan hosting option. However, if your logic app uses the **App Service Environment v3** hosting option, you can disable storage account key access."

## SKU Information

### ASEv3 Isolated SKUs (Used in this project)

| SKU | vCPU | Memory | Use Case |
|-----|------|--------|----------|
| **I1v2** | 2 | 8 GB | Development/Testing (selected) |
| I2v2 | 4 | 16 GB | Production workloads |
| I3v2 | 8 | 32 GB | High-performance workloads |

### Managed Identity Configuration

| Identity Type | Purpose | Roles Assigned |
|--------------|---------|----------------|
| **User-Assigned** | Storage Account Access | Storage Account Contributor, Storage Blob Data Owner, Storage Queue Data Contributor, Storage Table Data Contributor, Storage File Data Privileged Contributor |
| **System-Assigned** | Key Vault Secret Access | Key Vault Secrets User |

## Prerequisites

1. **Azure CLI** installed and authenticated (v2.50+)
2. **Terraform** >= 1.0.0
3. **Azure Subscription** with permissions to create ASEv3
4. **PowerShell** or **Bash** for running deployment scripts

## Project Structure

```
logicapp-tf/
├── README.md                    # This documentation
├── IMPLEMENTATION_DETAILS.md    # Detailed implementation documentation
├── main.tf                      # Main Terraform configuration
├── variables.tf                 # Variable definitions
├── outputs.tf                   # Output definitions
├── providers.tf                 # Provider configuration
├── terraform.tfvars             # Variable values (gitignored)
├── terraform.tfvars.example     # Example variable values
├── deploy.sh                    # Bash deployment script
├── deploy.ps1                   # PowerShell deployment script
├── destroy.ps1                  # Cleanup script
└── logic-app-src/               # Logic App source files
    ├── host.json                # Runtime configuration
    ├── connections.json         # Managed connections metadata
    ├── local.settings.json      # Local development settings (NOT deployed)
    ├── httpbin-workflow/        # Workflow folder
    │   └── workflow.json        # Workflow JSON definition
    └── workflow-designtime/     # Development-only settings (NOT deployed)
        ├── host.json
        └── local.settings.json
```

## Deployment Steps

### 1. Initialize Terraform

```bash
cd /mnt/c/dev/logicapp-tf
terraform init
```

### 2. Configure Variables

```bash
# Copy the example file and edit with your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred settings
```

Key variables:
```hcl
use_asev3     = true      # Required for identity-only storage
logic_app_sku = "I1v2"    # ASEv3 Isolated SKU
```

### 3. Plan and Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

**Note**: ASEv3 deployment takes approximately 30-40 minutes.

## App Settings Configuration

The Logic App is configured with identity-based storage authentication:

```hcl
app_settings = [
  { name = "FUNCTIONS_EXTENSION_VERSION", value = "~4" },
  { name = "FUNCTIONS_WORKER_RUNTIME", value = "dotnet" },
  { name = "AzureWebJobsStorage__managedIdentityResourceId", value = "<user-assigned-identity-id>" },
  { name = "AzureWebJobsStorage__blobServiceUri", value = "https://<storage>.blob.core.windows.net" },
  { name = "AzureWebJobsStorage__queueServiceUri", value = "https://<storage>.queue.core.windows.net" },
  { name = "AzureWebJobsStorage__tableServiceUri", value = "https://<storage>.table.core.windows.net" },
  { name = "AzureWebJobsStorage__credential", value = "managedidentity" },
  { name = "APP_KIND", value = "workflowApp" }
]
```

## Key Configuration Details

### Identity-Based Storage Access

Required app settings per [Microsoft Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account):

| App Setting | Value |
|-------------|-------|
| `AzureWebJobsStorage__managedIdentityResourceId` | Full resource ID of User-Assigned Managed Identity |
| `AzureWebJobsStorage__blobServiceUri` | Blob service endpoint URL |
| `AzureWebJobsStorage__queueServiceUri` | Queue service endpoint URL |
| `AzureWebJobsStorage__tableServiceUri` | Table service endpoint URL |
| `AzureWebJobsStorage__credential` | `managedidentity` |

### Key Vault References

Secrets are referenced using the format:
```
@Microsoft.KeyVault(VaultName=<vault-name>;SecretName=<secret-name>)
```

## Testing the Workflow

After deployment:

```bash
# Get the workflow endpoint
HOSTNAME=$(terraform output -raw logic_app_default_hostname)

# The workflow trigger URL can be obtained from Azure Portal
# Navigate to: Logic App → Workflows → httpbin-workflow → Workflow URL
```

## Security Considerations

1. **No Shared Key Access**: Storage account uses identity-based authentication only
2. **User-Assigned Identity**: Dedicated identity for storage access with least-privilege RBAC
3. **System-Assigned Identity**: Separate identity for Key Vault access
4. **Key Vault RBAC**: Uses `Key Vault Secrets User` role (least privilege)
5. **HTTPS Only**: Logic App enforces HTTPS connections
6. **ASEv3 External Mode**: Allows Azure Portal access while maintaining isolation

## Clean Up

```bash
terraform destroy
```

**Note**: ASEv3 destruction also takes approximately 30-40 minutes.

## Troubleshooting

### Storage Authentication Errors

If you see: `Microsoft.WindowsAzure.Storage: Value cannot be null. (Parameter 'connectionString')`

1. Verify all `AzureWebJobsStorage__*` app settings are configured
2. Ensure User-Assigned Identity has all required storage roles
3. Restart the Logic App after configuration changes

### ASEv3 Deployment Timeout

ASEv3 deployment takes 30-40 minutes. If timeout occurs:
```bash
terraform apply -refresh-only  # Refresh state
terraform apply                # Continue deployment
```

## Additional Resources

- [Logic App Standard with ASEv3](https://learn.microsoft.com/en-us/azure/logic-apps/single-tenant-overview-compare)
- [Identity-based Storage Authentication](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account)
- [Managed Identity in Logic Apps](https://learn.microsoft.com/en-us/azure/logic-apps/authenticate-with-managed-identity)
- [App Service Environment v3](https://learn.microsoft.com/en-us/azure/app-service/environment/overview)
