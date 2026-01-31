#!/bin/bash
# =============================================================================
# Deploy Logic App Workflow using Azure CLI
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Convert path for Windows if running in WSL
if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
    # Running in WSL - convert to Windows path for Azure CLI
    WIN_SCRIPT_DIR=$(wslpath -w "$SCRIPT_DIR")
    ZIP_FILE_WIN="$WIN_SCRIPT_DIR\\logic-app-package.zip"
else
    ZIP_FILE_WIN="$SCRIPT_DIR/logic-app-package.zip"
fi

echo "======================================"
echo "Logic App Workflow Deployment"
echo "======================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - read from terraform output or set defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-logicapp-tf}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-}"
SOURCE_DIR="$SCRIPT_DIR/logic-app-src"
ZIP_FILE="$SCRIPT_DIR/logic-app-package.zip"

# Get Logic App name from terraform output if not set
get_config() {
    echo -e "\n${YELLOW}Reading configuration from Terraform...${NC}"
    
    if [ -z "$LOGIC_APP_NAME" ]; then
        LOGIC_APP_NAME=$(terraform output -raw logic_app_name 2>/dev/null || echo "")
    fi
    
    if [ -z "$LOGIC_APP_NAME" ]; then
        echo -e "${RED}Error: Could not determine Logic App name.${NC}"
        echo -e "${YELLOW}Please set LOGIC_APP_NAME environment variable or run terraform apply first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Logic App: $LOGIC_APP_NAME${NC}"
    echo -e "${GREEN}✓ Resource Group: $RESOURCE_GROUP${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        echo -e "${RED}Error: Azure CLI is not installed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Azure CLI installed${NC}"
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        echo -e "${YELLOW}Not logged in to Azure. Running 'az login'...${NC}"
        az login
    fi
    echo -e "${GREEN}✓ Logged in to Azure${NC}"
    
    # Check Logic App extension
    az extension add --name logic --yes 2>/dev/null || true
    echo -e "${GREEN}✓ Azure Logic App extension ready${NC}"
    
    # Check source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo -e "${RED}Error: Source directory not found: $SOURCE_DIR${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Source directory found${NC}"
}

# Create ZIP package
create_package() {
    echo -e "\n${YELLOW}Creating deployment package...${NC}"
    
    # Remove old package
    rm -f "$ZIP_FILE"
    
    # Create ZIP - try multiple methods
    cd "$SOURCE_DIR"
    
    if command -v zip &> /dev/null; then
        # Use zip if available
        zip -r "$ZIP_FILE" . \
            -x "workflow-designtime/*" \
            -x "workflow-designtime" \
            -x "local.settings.json" \
            -x ".vscode/*" \
            -x ".vscode"
    elif command -v pwsh &> /dev/null; then
        # Use PowerShell if available
        pwsh -Command "Compress-Archive -Path '$SOURCE_DIR/*' -DestinationPath '$ZIP_FILE' -Force"
    elif command -v powershell.exe &> /dev/null; then
        # Use Windows PowerShell from WSL
        powershell.exe -Command "Compress-Archive -Path '$SOURCE_DIR/*' -DestinationPath '$ZIP_FILE' -Force"
    else
        # Fall back to tar and gzip converted to zip format
        echo -e "${RED}Error: No zip tool available. Please install zip.${NC}"
        echo -e "${YELLOW}On Ubuntu/Debian: sudo apt-get install zip${NC}"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
    
    echo -e "${GREEN}✓ Package created: $ZIP_FILE${NC}"
}

# Deploy the workflow
deploy_workflow() {
    echo -e "\n${YELLOW}Deploying workflow to Logic App...${NC}"
    echo -e "${YELLOW}This may take a few minutes...${NC}"
    
    # First try direct deployment
    echo -e "${YELLOW}Attempting direct ZIP deployment...${NC}"
    if az webapp deploy \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --src-path "$ZIP_FILE_WIN" \
        --type zip \
        --timeout 120 2>&1; then
        echo -e "${GREEN}✓ Workflow deployed successfully via direct upload${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Direct deployment failed. Trying deployment via Azure Storage...${NC}"
    
    # Get storage account name from terraform
    STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null || echo "")
    if [ -z "$STORAGE_ACCOUNT" ]; then
        echo -e "${RED}Error: Could not get storage account name from Terraform${NC}"
        return 1
    fi
    
    # Create deploy container and upload ZIP
    CONTAINER="logic-app-deploy"
    BLOB_NAME="logic-app-package-$(date +%s).zip"
    
    echo -e "${YELLOW}Uploading package to Azure Storage...${NC}"
    az storage container create \
        --account-name "$STORAGE_ACCOUNT" \
        --name "$CONTAINER" \
        --auth-mode login 2>/dev/null || true
    
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$BLOB_NAME" \
        --file "$ZIP_FILE_WIN" \
        --auth-mode login \
        --overwrite
    
    # Generate SAS URL (valid for 1 hour)
    EXPIRY=$(date -u -d "+1 hour" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -v+1H +%Y-%m-%dT%H:%MZ)
    SAS_URL=$(az storage blob generate-sas \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$BLOB_NAME" \
        --permissions r \
        --expiry "$EXPIRY" \
        --auth-mode login \
        --as-user \
        --full-uri \
        -o tsv)
    
    echo -e "${YELLOW}Deploying from Azure Storage URL...${NC}"
    az webapp deploy \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --src-url "$SAS_URL" \
        --type zip
    
    echo -e "${GREEN}✓ Workflow deployed successfully via Azure Storage${NC}"
}

# Verify deployment
verify_deployment() {
    echo -e "\n${YELLOW}Verifying deployment...${NC}"
    
    # List workflows
    echo -e "${YELLOW}Checking workflow status...${NC}"
    WORKFLOW_URL=$(az logicapp show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostName" -o tsv)
    
    echo -e "${GREEN}✓ Logic App URL: https://$WORKFLOW_URL${NC}"
}

# Main function
main() {
    echo -e "${YELLOW}Starting workflow deployment...${NC}"
    
    check_prerequisites
    get_config
    create_package
    deploy_workflow
    verify_deployment
    
    echo -e "\n${GREEN}======================================"
    echo -e "Workflow deployment completed!"
    echo -e "======================================${NC}"
    echo -e "\nYou can trigger the workflow using:"
    echo -e "  POST https://$(terraform output -raw logic_app_default_hostname 2>/dev/null || echo "$WORKFLOW_URL")/api/httpbin-workflow/triggers/manual/invoke?api-version=2022-05-01"
}

# Run main function
main "$@"
