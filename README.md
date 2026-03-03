# Azure Logic App Standard on Existing ASEv3 - Terraform Deployment

## Overview

This Terraform project deploys an Azure Logic App (Standard) to an **existing App Service Environment v3 (ASEv3)** with:
1. **Identity-based storage authentication** (no shared key access) - compliant with Azure Policy
2. **User-Assigned Managed Identity** for storage access with proper RBAC roles
3. **System-Assigned Managed Identity** for Key Vault secret access
4. **Private endpoints** for storage account (optional)
5. Demonstrates secure secret management using Key Vault references

> **Note**: This module does NOT create the ASE, VNet, or subnet. Those resources must be provisioned separately (e.g., by a platform team) before deploying this module.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                 EXISTING INFRASTRUCTURE (Managed Externally)                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                         Virtual Network (existing)                           ││
│  │                                                                              ││
│  │  ┌─────────────────────────────────┐  ┌──────────────────────────────────┐  ││
│  │  │   ASEv3 Subnet                  │  │   Private Endpoint Subnet        │  ││
│  │  │   Delegation: hostingEnvs       │  │   (for storage private links)    │  ││
│  │  │                                 │  │                                  │  ││
│  │  │  ┌───────────────────────────┐  │  │                                  │  ││
│  │  │  │  App Service Environment  │  │  │                                  │  ││
│  │  │  │  v3 (existing)            │  │  │                                  │  ││
│  │  │  │  Internal or External     │  │  │                                  │  ││
│  │  │  └───────────────────────────┘  │  │                                  │  ││
│  │  └─────────────────────────────────┘  └──────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
│                                                                                  │
│  Private DNS Zones (existing, managed by Azure Policy):                          │
│  • privatelink.blob.core.windows.net                                             │
│  • privatelink.file.core.windows.net                                             │
│  • privatelink.table.core.windows.net                                            │
│  • privatelink.queue.core.windows.net                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       │ References
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│              THIS MODULE - Resource Group (rg-logicapp-tf)                       │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                App Service Plan (Hosted in Existing ASE)                     ││
│  │                SKU: I1v2 (Isolated v2)                                       ││
│  │                                                                              ││
│  │   ┌─────────────────────────────────────────────────────────────────────┐   ││
│  │   │   Logic App Standard (workflowapp)                                  │   ││
│  │   │   .NET 8 In-Process Runtime                                         │   ││
│  │   │                                                                     │   ││
│  │   │   Identities:                                                       │   ││
│  │   │   • System-Assigned → Key Vault Secrets User                        │   ││
│  │   │   • User-Assigned → Storage RBAC Roles                              │   ││
│  │   └─────────────────────────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
│                                                                                  │
│  ┌─────────────────────────────┐       ┌──────────────────────────────────────┐ │
│  │   Azure Key Vault           │       │   Storage Account                    │ │
│  │   (RBAC Authorization)      │       │   allowSharedKeyAccess = false       │ │
│  │                             │       │   (identity-only authentication)     │ │
│  │   Secrets:                  │       │                                      │ │
│  │   - demo-username           │       │   Private Endpoints (optional):      │ │
│  │   - demo-password           │       │   - Blob, File, Table, Queue         │ │
│  │                             │       │                                      │ │
│  │   Role: Key Vault           │       │   Role Assignments (User Identity):  │ │
│  │   Secrets User              │       │   - Storage Account Contributor      │ │
│  │   (System Identity)         │       │   - Storage Blob Data Owner          │ │
│  │                             │       │   - Storage Queue Data Contributor   │ │
│  │                             │       │   - Storage Table Data Contributor   │ │
│  │                             │       │   - Storage File Data Privileged     │ │
│  └─────────────────────────────┘       └──────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────┐                                                │
│  │  User-Assigned Identity     │                                                │
│  │  (for storage access)       │                                                │
│  └─────────────────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Why ASEv3?

**Azure Policy Requirement**: When Azure Policy enforces `allowSharedKeyAccess = false` on storage accounts:
- **Workflow Service Plan (WS1/WS2/WS3)** does NOT support identity-only storage authentication
- **App Service Environment v3 (ASEv3)** is the ONLY hosting option that supports disabling storage account shared keys

Per [Microsoft Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account):
> "Currently, you can't disable storage account key access for Standard logic apps that use the Workflow Service Plan hosting option. However, if your logic app uses the **App Service Environment v3** hosting option, you can disable storage account key access."

## Prerequisites

### External Infrastructure (Must Exist Before Deployment)

This module requires the following resources to be provisioned externally:

| Resource | Description |
|----------|-------------|
| **ASEv3** | App Service Environment v3 with subnet delegation |
| **VNet** | Virtual Network containing the ASE subnet |
| **ASE Subnet** | Subnet with `Microsoft.Web/hostingEnvironments` delegation, /24 or larger |
| **PE Subnet** | Subnet for private endpoints (if using private endpoints) |
| **Private DNS Zones** | (Optional) If managed by Azure Policy for private endpoints |

### Local Requirements

1. **Azure CLI** installed and authenticated (v2.50+)
2. **Terraform** >= 1.0.0
3. **Azure Subscription** with Contributor access
4. **Network connectivity** to ASE (VPN/ExpressRoute for internal ASE)

## SKU Information

### ASEv3 Isolated SKUs

| SKU | vCPU | Memory | Use Case |
|-----|------|--------|----------|
| **I1v2** | 2 | 8 GB | Development/Testing (default) |
| I2v2 | 4 | 16 GB | Production workloads |
| I3v2 | 8 | 32 GB | High-performance workloads |

### Managed Identity Configuration

| Identity Type | Purpose | Roles Assigned |
|--------------|---------|----------------|
| **User-Assigned** | Storage Account Access | Storage Account Contributor, Storage Blob Data Owner, Storage Queue Data Contributor, Storage Table Data Contributor, Storage File Data Privileged Contributor |
| **System-Assigned** | Key Vault Secret Access | Key Vault Secrets User |

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
├── deploy-workflow.sh           # Workflow deployment script (WSL)
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
```

Key variables to configure:

```hcl
# Existing ASE Configuration (required)
use_existing_ase            = true
existing_ase_id             = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/hostingEnvironments/{ase-name}"
existing_ase_resource_group = "rg-ase"
existing_ase_name           = "ase-name"

# Existing Network Configuration (required)
existing_vnet_resource_group_name = "rg-network"
existing_vnet_name                = "vnet-hub"
existing_subnet_name              = "snet-ase"

# Private Endpoints (optional)
enable_private_endpoints = true
private_endpoint_subnet_id = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{pe-subnet}"

# If using existing Private DNS Zones (e.g., managed by Azure Policy)
create_private_dns_zones = false
existing_private_dns_zone_ids = {
  blob  = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  file  = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  table = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
  queue = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
}
```

### 3. Plan and Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Deploy Workflows

After Terraform completes, deploy the Logic App workflows:

```bash
./deploy-workflow.sh
```

## App Settings Configuration

The Logic App is configured with identity-based storage authentication and .NET 8 in-process runtime:

```hcl
app_settings = [
  { name = "FUNCTIONS_EXTENSION_VERSION", value = "~4" },
  { name = "FUNCTIONS_WORKER_RUNTIME", value = "dotnet" },
  { name = "FUNCTIONS_INPROC_NET8_ENABLED", value = "1" },
  { name = "AzureWebJobsStorage__managedIdentityResourceId", value = "<user-assigned-identity-id>" },
  { name = "AzureWebJobsStorage__blobServiceUri", value = "https://<storage>.blob.core.windows.net" },
  { name = "AzureWebJobsStorage__queueServiceUri", value = "https://<storage>.queue.core.windows.net" },
  { name = "AzureWebJobsStorage__tableServiceUri", value = "https://<storage>.table.core.windows.net" },
  { name = "AzureWebJobsStorage__credential", value = "managedidentity" },
  { name = "APP_KIND", value = "workflowApp" },
  { name = "WEBSITE_CONTENTOVERVNET", value = "1" },
  { name = "WEBSITE_VNET_ROUTE_ALL", value = "1" }
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

### .NET 8 In-Process Runtime

| App Setting | Value | Description |
|-------------|-------|-------------|
| `FUNCTIONS_EXTENSION_VERSION` | `~4` | Azure Functions runtime v4 |
| `FUNCTIONS_WORKER_RUNTIME` | `dotnet` | .NET runtime |
| `FUNCTIONS_INPROC_NET8_ENABLED` | `1` | Enable .NET 8 in-process model |
| `netFrameworkVersion` | `v8.0` | Site config setting |

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

> **Note**: For internal ASE (mode: "Web, Publishing"), you must access the Logic App designer from within the VNet (via VPN, ExpressRoute, or Bastion).

## Security Considerations

1. **No Shared Key Access**: Storage account uses identity-based authentication only
2. **User-Assigned Identity**: Dedicated identity for storage access with least-privilege RBAC
3. **System-Assigned Identity**: Separate identity for Key Vault access
4. **Key Vault RBAC**: Uses `Key Vault Secrets User` role (least privilege)
5. **HTTPS Only**: Logic App enforces HTTPS connections
6. **Private Endpoints**: Optional private connectivity to storage account
7. **VNet Integration**: All traffic routed through VNet when enabled

## Clean Up

```bash
terraform destroy
```

## Troubleshooting

### Storage Authentication Errors

If you see: `Microsoft.WindowsAzure.Storage: Value cannot be null. (Parameter 'connectionString')`

1. Verify all `AzureWebJobsStorage__*` app settings are configured
2. Ensure User-Assigned Identity has all required storage roles
3. Wait 5-10 minutes for RBAC propagation
4. Restart the Logic App after configuration changes

### "Cannot reach host runtime" Error

This error occurs when:
- Logic App has private endpoints but designer is accessed from public network
- VNet routing is misconfigured

**Solution**: Access the Logic App designer from within the VNet (VPN/ExpressRoute/Bastion).

### DNS Resolution Issues (Internal ASE)

For internal ASE, ensure:
1. Private DNS zone `{ase-name}.appserviceenvironment.net` is linked to VNet
2. DNS forwarders are configured if using custom DNS
3. Client machine can resolve ASE hostname

### Import Existing Resources

If `terraform apply` reports resource already exists:
```bash
terraform import azurerm_service_plan.logic_app "<resource-id>"
terraform apply
```

## Additional Resources

- [Logic App Standard with ASEv3](https://learn.microsoft.com/en-us/azure/logic-apps/single-tenant-overview-compare)
- [Identity-based Storage Authentication](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account)
- [Managed Identity in Logic Apps](https://learn.microsoft.com/en-us/azure/logic-apps/authenticate-with-managed-identity)
- [App Service Environment v3](https://learn.microsoft.com/en-us/azure/app-service/environment/overview)
- [Private Networking for Logic Apps](https://learn.microsoft.com/en-us/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint)
