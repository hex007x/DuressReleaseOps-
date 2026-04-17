param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [string]$TargetPath = "C:\ProgramData\DuressAlert\TrustedLicenseKeys.xml",

    [switch]$BackupExisting
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $SourcePath)) {
    throw "Trusted key bundle was not found: $SourcePath"
}

$targetDirectory = Split-Path -Parent $TargetPath
if ([string]::IsNullOrWhiteSpace($targetDirectory)) {
    throw "Could not determine target directory from $TargetPath"
}

if (!(Test-Path $targetDirectory)) {
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

if ($BackupExisting -and (Test-Path $TargetPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $targetDirectory ("TrustedLicenseKeys.{0}.bak.xml" -f $timestamp)
    Copy-Item -Path $TargetPath -Destination $backupPath -Force
    Write-Host "Backed up existing trust bundle to $backupPath"
}

[xml]$trustedKeys = Get-Content -Path $SourcePath
if ($trustedKeys.DocumentElement.Name -ne "TrustedLicenseKeys") {
    throw "The supplied XML is not a TrustedLicenseKeys document."
}

$keys = @($trustedKeys.SelectNodes("/TrustedLicenseKeys/Key"))
if ($keys.Count -lt 1) {
    throw "The supplied trust bundle does not contain any <Key> entries."
}

Copy-Item -Path $SourcePath -Destination $TargetPath -Force
Write-Host "Deployed trusted key bundle to $TargetPath"
Write-Host ("Trusted keys deployed: {0}" -f $keys.Count)
