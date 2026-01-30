# =============================================================================
# Destroy Script for Azure Logic App Resources
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Logic App Terraform Destroy Script" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Write-Host "`nWARNING: This will destroy all resources created by Terraform!" -ForegroundColor Red
Write-Host "Resources to be destroyed:" -ForegroundColor Yellow

terraform plan -destroy -out=destroy-plan

Write-Host "`nAre you sure you want to destroy all resources? (yes/no)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "yes") {
    Write-Host "`nDestroying resources..." -ForegroundColor Yellow
    terraform apply destroy-plan
    Write-Host "`nResources destroyed successfully!" -ForegroundColor Green
    Remove-Item -Path "destroy-plan" -ErrorAction SilentlyContinue
}
else {
    Write-Host "Destroy cancelled." -ForegroundColor Yellow
    Remove-Item -Path "destroy-plan" -ErrorAction SilentlyContinue
}
