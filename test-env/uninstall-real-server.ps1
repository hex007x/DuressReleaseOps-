<#
.SYNOPSIS
Uninstalls the local Duress Alert Windows server service used in the real-service test flow.

.DESCRIPTION
Stops and removes the `DuressAlertService` Windows service if it exists.
If a prior backup of `Settings.xml`, `License.dat`, or `License.v3.xml` exists
under the sandbox backup folder, those files are restored. Otherwise the current
copies are removed.

This script is aimed at test/rehearsal cleanup, not polished customer uninstall UX.

If you want to remove both server and client together, use:
`test-env\\cleanup-duress-server-and-client.ps1`

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\uninstall-real-server.ps1

Stops and uninstalls the DuressAlertService test install and restores prior
server config where possible.

.NOTES
Script version: 2026.04.13.1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverExe = Join-Path $scriptRoot "server-build\DuressServer.exe"
$serviceName = "DuressAlertService"
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$backupRoot = Join-Path $scriptRoot "sandbox\real-server-backup"
$markerFile = Join-Path $runtimeRoot "real-server-backup.marker"
$serviceModeFile = Join-Path $runtimeRoot "server-mode.txt"

$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$settingsFile = Join-Path $programDataRoot "Settings.xml"
$licenseFile = Join-Path $programDataRoot "License.dat"
$signedLicenseFile = Join-Path $programDataRoot "License.v3.xml"

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
  if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    if ($PSCmdlet.ShouldProcess($serviceName, 'Stop server service')) {
      Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
      $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(15))
    }
  }

  if ($PSCmdlet.ShouldProcess($serviceName, 'Uninstall server service')) {
    if (Test-Path $serverExe) {
      & $serverExe /uninstall
    } else {
      sc.exe delete $serviceName | Out-Null
    }
  }
}

if (Test-Path (Join-Path $backupRoot "Settings.xml")) {
  if ($PSCmdlet.ShouldProcess($settingsFile, 'Restore Settings.xml backup')) {
    $settingsDir = Split-Path -Parent $settingsFile
    if (-not [string]::IsNullOrWhiteSpace($settingsDir) -and -not (Test-Path $settingsDir)) {
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    Copy-Item (Join-Path $backupRoot "Settings.xml") $settingsFile -Force
  }
} else {
  if ($PSCmdlet.ShouldProcess($settingsFile, 'Remove current Settings.xml')) {
    Remove-Item $settingsFile -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path (Join-Path $backupRoot "License.dat")) {
  if ($PSCmdlet.ShouldProcess($licenseFile, 'Restore License.dat backup')) {
    $licenseDir = Split-Path -Parent $licenseFile
    if (-not [string]::IsNullOrWhiteSpace($licenseDir) -and -not (Test-Path $licenseDir)) {
      New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
    }
    Copy-Item (Join-Path $backupRoot "License.dat") $licenseFile -Force
  }
} else {
  if ($PSCmdlet.ShouldProcess($licenseFile, 'Remove current License.dat')) {
    Remove-Item $licenseFile -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path (Join-Path $backupRoot "License.v3.xml")) {
  if ($PSCmdlet.ShouldProcess($signedLicenseFile, 'Restore License.v3.xml backup')) {
    $signedLicenseDir = Split-Path -Parent $signedLicenseFile
    if (-not [string]::IsNullOrWhiteSpace($signedLicenseDir) -and -not (Test-Path $signedLicenseDir)) {
      New-Item -ItemType Directory -Path $signedLicenseDir -Force | Out-Null
    }
    Copy-Item (Join-Path $backupRoot "License.v3.xml") $signedLicenseFile -Force
  }
} else {
  if ($PSCmdlet.ShouldProcess($signedLicenseFile, 'Remove current License.v3.xml')) {
    Remove-Item $signedLicenseFile -Force -ErrorAction SilentlyContinue
  }
}

if ($PSCmdlet.ShouldProcess($markerFile, 'Remove marker file')) {
  Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
}
if ($PSCmdlet.ShouldProcess($serviceModeFile, 'Remove service mode file')) {
  Remove-Item $serviceModeFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Uninstalled real server service and restored prior server config where possible."
