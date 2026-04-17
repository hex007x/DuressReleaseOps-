param(
    [Parameter(Mandatory = $true)]
    [string]$CloudClaimUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClaimToken,

    [string]$LicenseApiToken = '',

    [string]$ServerExePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot

if ([string]::IsNullOrWhiteSpace($ServerExePath)) {
    $ServerExePath = Join-Path $workspaceRoot '_external\DuressServer2025\DuressServer2025\bin\Debug\DuressServer.exe'
}

if (-not (Test-Path $ServerExePath)) {
    throw "Server executable not found at '$ServerExePath'. Build the v3 server first."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dataRoot = Join-Path (Join-Path $scriptRoot 'sandbox') "server-cloud-claim-$timestamp"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null

$previousDataRoot = $env:DURESS_SERVER_DATA_ROOT
$env:DURESS_SERVER_DATA_ROOT = $dataRoot

try {
    [System.Reflection.Assembly]::LoadFrom($ServerExePath) | Out-Null

    [DuressAlert.ConfigManager]::EnsureFoldersExist()

    $settings = [DuressAlert.ConfigManager]::LoadSettings()
    $settings.IP = [System.Net.IPAddress]::Loopback
    $settings.CloudClaimUrl = $CloudClaimUrl
    $settings.CloudClaimToken = $ClaimToken
    $settings.LicenseApiToken = $LicenseApiToken
    [DuressAlert.ConfigManager]::SaveSettings($settings)

    $response = $null
    $message = ''
    $ok = [DuressAlert.LicenseManager]::TryClaimCloudSystem($settings, [ref]$response, [ref]$message)

    $runtimeStatus = [DuressAlert.ConfigManager]::LoadLicenseRuntimeStatus()
    $runtimeStatus.LastCloudCheckUtc = [DateTime]::UtcNow
    $runtimeStatus.LastCloudCheckResult = $message
    $runtimeStatus.LastCloudLicenseState = if ($ok) { 'Claimed' } else { 'Claim Failed' }
    [DuressAlert.ConfigManager]::SaveLicenseRuntimeStatus($runtimeStatus)
}
finally {
    $env:DURESS_SERVER_DATA_ROOT = $previousDataRoot
}

$runtimeStatusPath = Join-Path $dataRoot 'LicenseRuntimeStatus.xml'
$signedLicensePath = Join-Path $dataRoot 'License.v3.xml'

Write-Host "Isolated data root: $dataRoot"
Write-Host ("Success: " + $ok)
Write-Host ("Message: " + $message)

if ($response) {
    if (-not [string]::IsNullOrWhiteSpace($response.CustomerName)) {
        Write-Host ("Customer: " + $response.CustomerName)
    }

    if (-not [string]::IsNullOrWhiteSpace($response.SystemName)) {
        Write-Host ("System: " + $response.SystemName)
    }

    if (-not [string]::IsNullOrWhiteSpace($response.LicenseSerial)) {
        Write-Host ("License: " + $response.LicenseSerial)
    }
}

if (Test-Path $signedLicensePath) {
    [xml]$licenseXml = Get-Content -Path $signedLicensePath
    Write-Host ''
    Write-Host 'Installed signed license:'
    Write-Host ("LicenseId: " + [string]$licenseXml.License.LicenseId)
    Write-Host ("CustomerName: " + [string]$licenseXml.License.CustomerName)
    Write-Host ("LicenseType: " + [string]$licenseXml.License.LicenseType)
    Write-Host ("ExpiresAtUtc: " + [string]$licenseXml.License.ExpiresAtUtc)
    Write-Host ("MaxClients: " + [string]$licenseXml.License.MaxClients)
    Write-Host ("ServerFingerprint: " + [string]$licenseXml.License.ServerFingerprint)
}
else {
    Write-Host ''
    Write-Host 'Installed signed license: none'
}

if (Test-Path $runtimeStatusPath) {
    [xml]$runtimeXml = Get-Content -Path $runtimeStatusPath
    Write-Host ''
    Write-Host 'Runtime status:'
    Write-Host ("LastCloudCheckResult: " + [string]$runtimeXml.LicenseRuntimeStatus.LastCloudCheckResult)
    Write-Host ("LastCloudLicenseState: " + [string]$runtimeXml.LicenseRuntimeStatus.LastCloudLicenseState)
}

if (-not $ok) {
    throw "Cloud claim failed."
}
