param(
    [Parameter(Mandatory = $true)]
    [string]$CloudCheckinUrl,

    [Parameter(Mandatory = $true)]
    [string]$SignedLicensePath,

    [string]$TrustedKeysPath = '',

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

if (-not (Test-Path $SignedLicensePath)) {
    throw "Signed license file not found at '$SignedLicensePath'."
}

if (-not [string]::IsNullOrWhiteSpace($TrustedKeysPath) -and -not (Test-Path $TrustedKeysPath)) {
    throw "Trusted key bundle not found at '$TrustedKeysPath'."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dataRoot = Join-Path (Join-Path $scriptRoot 'sandbox') "server-cloud-checkin-$timestamp"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null

$previousDataRoot = $env:DURESS_SERVER_DATA_ROOT
$env:DURESS_SERVER_DATA_ROOT = $dataRoot

try {
    [System.Reflection.Assembly]::LoadFrom($ServerExePath) | Out-Null

    [DuressAlert.ConfigManager]::EnsureFoldersExist()
    Copy-Item -Path $SignedLicensePath -Destination ([DuressAlert.ConfigManager]::SignedLicenseFile) -Force
    if (-not [string]::IsNullOrWhiteSpace($TrustedKeysPath)) {
        Copy-Item -Path $TrustedKeysPath -Destination (Join-Path $dataRoot 'TrustedLicenseKeys.xml') -Force
    }

    $settings = [DuressAlert.ConfigManager]::LoadSettings()
    $settings.IP = [System.Net.IPAddress]::Loopback
    $settings.CloudCheckinUrl = $CloudCheckinUrl
    $settings.LicenseApiToken = $LicenseApiToken
    [DuressAlert.ConfigManager]::SaveSettings($settings)

    $refreshed = $null
    $message = ''
    $status = ''
    $ok = [DuressAlert.LicenseManager]::TryRefreshLicenseFromConfiguredCloud($settings, [ref]$refreshed, [ref]$message, [ref]$status)

    $runtimeStatus = [DuressAlert.ConfigManager]::LoadLicenseRuntimeStatus()
    $runtimeStatus.LastCloudCheckUtc = [DateTime]::UtcNow
    $runtimeStatus.LastCloudCheckResult = $message
    $runtimeStatus.LastCloudLicenseState = if ([string]::IsNullOrWhiteSpace($status)) { if ($ok) { 'Current' } else { 'Failed' } } else { $status }
    [DuressAlert.ConfigManager]::SaveLicenseRuntimeStatus($runtimeStatus)
}
finally {
    $env:DURESS_SERVER_DATA_ROOT = $previousDataRoot
}

$runtimeStatusPath = Join-Path $dataRoot 'LicenseRuntimeStatus.xml'

Write-Host "Isolated data root: $dataRoot"
Write-Host ("Success: " + $ok)
Write-Host ("Message: " + $message)
Write-Host ("Cloud status: " + $status)

if ($refreshed) {
    Write-Host ("License ID: " + $refreshed.LicenseId)
    Write-Host ("Customer: " + $refreshed.CustomerName)
    Write-Host ("Max clients: " + $refreshed.MaxClients)
}

if (Test-Path $runtimeStatusPath) {
    [xml]$runtimeXml = Get-Content -Path $runtimeStatusPath
    Write-Host ''
    Write-Host 'Runtime status:'
    Write-Host ("LastCloudCheckResult: " + [string]$runtimeXml.LicenseRuntimeStatus.LastCloudCheckResult)
    Write-Host ("LastCloudLicenseState: " + [string]$runtimeXml.LicenseRuntimeStatus.LastCloudLicenseState)
}

if (-not $ok) {
    throw "Cloud check-in failed."
}
