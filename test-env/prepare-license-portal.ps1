param(
  [int]$CurrentValidDays = 30,
  [int]$RenewedValidDays = 395,
  [int]$CurrentMaxClients = 2,
  [int]$RenewedMaxClients = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portalRoot = Join-Path $scriptRoot "sandbox\runtime\license-portal"
$currentLicense = Join-Path $portalRoot "current-license.xml"
$renewedLicense = Join-Path $portalRoot "renewed-license.xml"
$invalidLicense = Join-Path $portalRoot "invalid-license.xml"
$activeModeFile = Join-Path $portalRoot "active-mode.txt"

New-Item -ItemType Directory -Force -Path $portalRoot | Out-Null

& (Join-Path $scriptRoot "issue-test-license.ps1") `
  -CustomerName "Local Test Customer" `
  -LicenseId "LIC-LOCAL-REAL-SERVER" `
  -LicenseType Subscription `
  -MaxClients $CurrentMaxClients `
  -ValidDays $CurrentValidDays `
  -OutputPath $currentLicense | Out-Null

& (Join-Path $scriptRoot "issue-test-license.ps1") `
  -CustomerName "Local Test Customer" `
  -LicenseId "LIC-LOCAL-REAL-SERVER" `
  -LicenseType Subscription `
  -MaxClients $RenewedMaxClients `
  -ValidDays $RenewedValidDays `
  -OutputPath $renewedLicense | Out-Null

$invalidXml = Get-Content $renewedLicense -Raw
$invalidXml = $invalidXml -replace "<Signature>.*?</Signature>", "<Signature>invalid-signature</Signature>"
Set-Content -Path $invalidLicense -Value $invalidXml -Encoding UTF8

Set-Content -Path $activeModeFile -Value "current" -Encoding ASCII

Write-Host "Prepared local license portal data:"
Write-Host "  Current :" $currentLicense
Write-Host "  Renewed :" $renewedLicense
Write-Host "  Invalid :" $invalidLicense
Write-Host "  Mode    : current"
