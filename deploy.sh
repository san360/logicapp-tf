#!/bin/bash
# =============================================================================
# Deploy Script for Azure Logic App with Terraform
# =============================================================================

set -e

echo "======================================"
echo "Logic App Terraform Deployment Script"
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
    
    # Check Logic App extension
    echo -e "${YELLOW}Ensuring Azure Logic App CLI extension is installed...${NC}"
    az extension add --name logic --yes 2>/dev/null || true
    echo -e "${GREEN}✓ Azure Logic App extension ready${NC}"
}

# Initialize Terraform
init_terraform() {
    echo -e "\n${YELLOW}Initializing Terraform...${NC}"
    terraform init
    echo -e "${GREEN}✓ Terraform initialized${NC}"
}

# Validate Terraform configuration
validate_terraform() {
    echo -e "\n${YELLOW}Validating Terraform configuration...${NC}"
    terraform validate
    echo -e "${GREEN}✓ Terraform configuration is valid${NC}"
}

# Plan Terraform deployment
plan_terraform() {
    echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
    terraform plan -out=tfplan
    echo -e "${GREEN}✓ Terraform plan created${NC}"
}

# Apply Terraform deployment
apply_terraform() {
    echo -e "\n${YELLOW}Applying Terraform deployment...${NC}"
    terraform apply tfplan
    echo -e "${GREEN}✓ Terraform deployment complete${NC}"
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
    echo -e "${YELLOW}Starting deployment...${NC}"
    
    check_prerequisites
    init_terraform
    validate_terraform
    plan_terraform
    
    echo -e "\n${YELLOW}Ready to deploy. Do you want to proceed? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        apply_terraform
        show_outputs
        echo -e "\n${GREEN}Deployment completed successfully!${NC}"
    else
        echo -e "${YELLOW}Deployment cancelled.${NC}"
        rm -f tfplan
    fi
}

# Run main function
main "$@"
