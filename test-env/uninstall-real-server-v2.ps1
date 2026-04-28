<#
.SYNOPSIS
Uninstalls the local Duress Alert Windows server service used in the real-service test flow.

.DESCRIPTION
Stops and removes the `DuressAlertService` Windows service if it exists.
If a prior backup of `Settings.xml`, `License.dat`, `License.v3.xml`, or
`TrustedLicenseKeys.xml` exists
under the sandbox backup folder, those files are restored. Otherwise the current
copies are removed.

This script is aimed at test/rehearsal cleanup, not polished customer uninstall UX.

If you want to remove both server and client together, use:
`test-env\\cleanup-duress-server-and-client-v2.ps1`

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\uninstall-real-server-v2.ps1

Stops and uninstalls the DuressAlertService test install and restores prior
server config where possible.

.NOTES
Script version: 2026.04.23.2
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
$trustedLicenseKeysFile = Join-Path $programDataRoot "TrustedLicenseKeys.xml"

function Restore-Or-RemoveProgramDataFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFileName,
    [Parameter(Mandatory = $true)]
    [string]$TargetFilePath
  )

  $backupFilePath = Join-Path $backupRoot $BackupFileName

  if (Test-Path $backupFilePath) {
    if ($PSCmdlet.ShouldProcess($TargetFilePath, ('Restore ' + $BackupFileName + ' backup'))) {
      $targetDir = Split-Path -Parent $TargetFilePath
      if (-not [string]::IsNullOrWhiteSpace($targetDir) -and -not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
      }
      Copy-Item $backupFilePath $TargetFilePath -Force
    }
  } else {
    if ($PSCmdlet.ShouldProcess($TargetFilePath, ('Remove current ' + $BackupFileName))) {
      Remove-Item $TargetFilePath -Force -ErrorAction SilentlyContinue
    }
  }
}

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

Restore-Or-RemoveProgramDataFile -BackupFileName "Settings.xml" -TargetFilePath $settingsFile
Restore-Or-RemoveProgramDataFile -BackupFileName "License.dat" -TargetFilePath $licenseFile
Restore-Or-RemoveProgramDataFile -BackupFileName "License.v3.xml" -TargetFilePath $signedLicenseFile
Restore-Or-RemoveProgramDataFile -BackupFileName "TrustedLicenseKeys.xml" -TargetFilePath $trustedLicenseKeysFile

if ($PSCmdlet.ShouldProcess($markerFile, 'Remove marker file')) {
  Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
}
if ($PSCmdlet.ShouldProcess($serviceModeFile, 'Remove service mode file')) {
  Remove-Item $serviceModeFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Uninstalled real server service and restored prior server config where possible."
