param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\claimed-operator-rollout-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$ClaimToken = "DEV-CLAIM-DEFAULT",
  [string]$CloudSystemName = "Main Reception Server",
  [string]$CloudPortalUrl = "http://localhost:5186",
  [string]$CloudClaimUrl = "http://localhost:5186/api/systems/claim",
  [string]$CloudCheckinUrl = "http://localhost:5186/api/licensing/checkin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$operatorSuite = Join-Path $scriptRoot "exercise-operator-rollout-regression-suite.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File $operatorSuite `
  -OutputRoot $OutputRoot `
  -UseCloudClaim `
  -FetchInstallersFromCloud `
  -FetchServerInstallerFromCloud `
  -ClaimToken $ClaimToken `
  -CloudSystemName $CloudSystemName `
  -CloudPortalUrl $CloudPortalUrl `
  -CloudClaimUrl $CloudClaimUrl `
  -CloudCheckinUrl $CloudCheckinUrl

if ($LASTEXITCODE -ne 0) {
  throw "Claimed operator rollout regression suite failed."
}
