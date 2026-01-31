#!/bin/bash
# =============================================================================
# Deploy Script for Azure Logic App Infrastructure (Terraform)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Logic App Infrastructure Deployment"
echo "======================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Error: Terraform is not installed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Terraform installed: $(terraform version | head -1)${NC}"
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        echo -e "${RED}Error: Azure CLI is not installed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Azure CLI installed: $(az version --query '"azure-cli"' -o tsv)${NC}"
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        echo -e "${YELLOW}Not logged in to Azure. Running 'az login'...${NC}"
        az login
    fi
    echo -e "${GREEN}✓ Logged in to Azure${NC}"
}

# Initialize Terraform
init_terraform() {
    echo -e "\n${YELLOW}Initializing Terraform...${NC}"
    terraform init
    echo -e "${GREEN}✓ Terraform initialized${NC}"
}

# Apply Terraform deployment
apply_terraform() {
    echo -e "\n${YELLOW}Applying Terraform deployment...${NC}"
    terraform apply -auto-approve
    echo -e "${GREEN}✓ Infrastructure deployment complete${NC}"
}

# Show outputs
show_outputs() {
    echo -e "\n${YELLOW}Deployment Outputs:${NC}"
    echo "======================================"
    terraform output
    echo "======================================"
}

# Main deployment
main() {
    echo -e "${YELLOW}Starting infrastructure deployment...${NC}"
    
    check_prerequisites
    init_terraform
    apply_terraform
    show_outputs
    
    echo -e "\n${GREEN}Infrastructure deployment completed!${NC}"
    echo -e "\n${YELLOW}To deploy the Logic App workflow, run:${NC}"
    echo -e "  ./deploy-workflow.sh"
}

# Run main function
main "$@"
