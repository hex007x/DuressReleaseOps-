param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\msi-upgrade-metadata\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudArtifactsRoot = Join-Path $workspaceRoot "DuressCloud\artifacts\installers"
$summaryPath = Join-Path $OutputRoot "MSI_UPGRADE_METADATA_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Get-MsiProperty {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$PropertyName
  )

  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($Path, 0))
  $query = "SELECT `Value` FROM `Property` WHERE `Property`='$PropertyName'"
  $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, ($query))
  $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null
  $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
  if ($null -eq $record) {
    return ""
  }

  return [string]$record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
}

function Get-PackagePair {
  param([Parameter(Mandatory = $true)][string]$Pattern)

  $matches = Get-ChildItem -Path $cloudArtifactsRoot -Recurse -Filter $Pattern -File |
    Sort-Object LastWriteTime -Descending |
    Group-Object Name |
    ForEach-Object { $_.Group | Select-Object -First 1 }

  $latest = $matches | Select-Object -First 1
  $previous = $matches | Select-Object -Skip 1 -First 1
  if (-not $latest -or -not $previous) {
    throw "Could not find both current and previous MSI artifacts for pattern '$Pattern'."
  }

  return @($latest, $previous)
}

function Assert-MsiUpgradeMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][System.IO.FileInfo]$Current,
    [Parameter(Mandatory = $true)][System.IO.FileInfo]$Previous
  )

  $currentVersion = Get-MsiProperty -Path $Current.FullName -PropertyName "ProductVersion"
  $previousVersion = Get-MsiProperty -Path $Previous.FullName -PropertyName "ProductVersion"
  $currentProductCode = Get-MsiProperty -Path $Current.FullName -PropertyName "ProductCode"
  $previousProductCode = Get-MsiProperty -Path $Previous.FullName -PropertyName "ProductCode"
  $currentUpgradeCode = Get-MsiProperty -Path $Current.FullName -PropertyName "UpgradeCode"
  $previousUpgradeCode = Get-MsiProperty -Path $Previous.FullName -PropertyName "UpgradeCode"
  $currentName = Get-MsiProperty -Path $Current.FullName -PropertyName "ProductName"

  if ([version]$currentVersion -le [version]$previousVersion) {
    throw "$Label MSI version did not advance. Current: $currentVersion Previous: $previousVersion"
  }

  if ([string]::Equals($currentProductCode, $previousProductCode, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label MSI ProductCode did not change between versions."
  }

  if (-not [string]::Equals($currentUpgradeCode, $previousUpgradeCode, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label MSI UpgradeCode changed between versions."
  }

  return [pscustomobject]@{
    Label = $Label
    ProductName = $currentName
    CurrentPath = $Current.FullName
    CurrentFile = $Current.Name
    CurrentVersion = $currentVersion
    PreviousPath = $Previous.FullName
    PreviousFile = $Previous.Name
    PreviousVersion = $previousVersion
    UpgradeCode = $currentUpgradeCode
  }
}

$clientPair = Get-PackagePair -Pattern "Duress.Alert.Client*.msi"
$serverPair = Get-PackagePair -Pattern "Duress.Alert.Server*.msi"
$results = @(
  Assert-MsiUpgradeMetadata -Label "Client" -Current $clientPair[0] -Previous $clientPair[1]
  Assert-MsiUpgradeMetadata -Label "Server" -Current $serverPair[0] -Previous $serverPair[1]
)

$lines = @()
$lines += "# MSI Upgrade Metadata Suite"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Coverage"
$lines += ""
$lines += "- Confirms current and previous client MSI artifacts exist"
$lines += "- Confirms current and previous server MSI artifacts exist"
$lines += "- Verifies product version increases between the previous and current package"
$lines += "- Verifies ProductCode changes for upgrade-safe packaging"
$lines += "- Verifies UpgradeCode stays stable across versions"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $lines += "- $($result.Label): $($result.ProductName) advanced from $($result.PreviousVersion) to $($result.CurrentVersion)"
  $lines += "  Current: [$($result.CurrentFile)]($($result.CurrentPath -replace '\\','/'))"
  $lines += "  Previous: [$($result.PreviousFile)]($($result.PreviousPath -replace '\\','/'))"
  $lines += "  UpgradeCode: $($result.UpgradeCode)"
}

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

Write-Host "MSI upgrade metadata suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
