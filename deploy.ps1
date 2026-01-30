# =============================================================================
# Deploy Script for Azure Logic App with Terraform (PowerShell)
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Logic App Terraform Deployment Script" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# Check prerequisites
function Test-Prerequisites {
    Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow
    
    # Check Terraform
    try {
        $tfVersion = terraform version
        Write-Host "✓ Terraform installed" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Terraform is not installed" -ForegroundColor Red
        exit 1
    }
    
    # Check Azure CLI
    try {
        $azVersion = az version --query '"azure-cli"' -o tsv
        Write-Host "✓ Azure CLI installed: $azVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Azure CLI is not installed" -ForegroundColor Red
        exit 1
    }
    
    # Check Azure login
    try {
        $account = az account show 2>$null
        Write-Host "✓ Logged in to Azure" -ForegroundColor Green
    }
    catch {
        Write-Host "Not logged in to Azure. Running 'az login'..." -ForegroundColor Yellow
        az login
    }
    
    # Ensure Logic App extension
    Write-Host "Ensuring Azure Logic App CLI extension is installed..." -ForegroundColor Yellow
    az extension add --name logic --yes 2>$null
    Write-Host "✓ Azure Logic App extension ready" -ForegroundColor Green
}

# Initialize Terraform
function Initialize-Terraform {
    Write-Host "`nInitializing Terraform..." -ForegroundColor Yellow
    terraform init
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed" }
    Write-Host "✓ Terraform initialized" -ForegroundColor Green
}

# Validate Terraform configuration
function Test-TerraformConfig {
    Write-Host "`nValidating Terraform configuration..." -ForegroundColor Yellow
    terraform validate
    if ($LASTEXITCODE -ne 0) { throw "Terraform validation failed" }
    Write-Host "✓ Terraform configuration is valid" -ForegroundColor Green
}

# Plan Terraform deployment
function New-TerraformPlan {
    Write-Host "`nPlanning Terraform deployment..." -ForegroundColor Yellow
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed" }
    Write-Host "✓ Terraform plan created" -ForegroundColor Green
}

# Apply Terraform deployment
function Invoke-TerraformApply {
    Write-Host "`nApplying Terraform deployment..." -ForegroundColor Yellow
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed" }
    Write-Host "✓ Terraform deployment complete" -ForegroundColor Green
}

# Show outputs
function Show-Outputs {
    Write-Host "`nDeployment Outputs:" -ForegroundColor Yellow
    Write-Host "======================================" -ForegroundColor Cyan
    terraform output
    Write-Host "======================================" -ForegroundColor Cyan
}

# Main deployment
function Start-Deployment {
    Write-Host "Starting deployment..." -ForegroundColor Yellow
    
    Test-Prerequisites
    Initialize-Terraform
    Test-TerraformConfig
    New-TerraformPlan
    
    Write-Host "`nReady to deploy. Do you want to proceed? (y/n)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -match "^[yY]") {
        Invoke-TerraformApply
        Show-Outputs
        Write-Host "`nDeployment completed successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        Remove-Item -Path "tfplan" -ErrorAction SilentlyContinue
    }
}

# Run main function
Start-Deployment
