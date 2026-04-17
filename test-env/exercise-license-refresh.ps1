param(
  [switch]$UseRenewedLicense,
  [int]$WaitSeconds = 75
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$signedLicenseFile = Join-Path $programDataRoot "License.v3.xml"
$runtimeStatusFile = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"
$serverLog = Join-Path $programDataRoot "Logs\DuressAlert_$(Get-Date -Format 'yyyyMMdd').log"
$portalLog = Join-Path $scriptRoot "sandbox\runtime\license-portal\license-portal.log"

& (Join-Path $scriptRoot "prepare-license-portal.ps1")
& (Join-Path $scriptRoot "start-license-portal.ps1")
& (Join-Path $scriptRoot "configure-real-server-license-portal.ps1") -CheckHours 1

if ($UseRenewedLicense) {
  & (Join-Path $scriptRoot "set-license-portal-response.ps1") -Mode renewed
} else {
  & (Join-Path $scriptRoot "set-license-portal-response.ps1") -Mode current
}

Write-Host "Restarting the real service so it picks up portal settings..."
Restart-Service -Name DuressAlertService -Force
Start-Sleep -Seconds $WaitSeconds

[xml]$licenseXml = Get-Content $signedLicenseFile
[xml]$runtimeXml = Get-Content $runtimeStatusFile

[PSCustomObject]@{
  PortalMode = if ($UseRenewedLicense) { "renewed" } else { "current" }
  InstalledMaxClients = $licenseXml.SelectSingleNode("/License/MaxClients").InnerText
  InstalledExpiresAtUtc = $licenseXml.SelectSingleNode("/License/ExpiresAtUtc").InnerText
  LastCloudCheckUtc = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudCheckUtc").InnerText
  LastCloudCheckResult = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudCheckResult").InnerText
  LastCloudLicenseState = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudLicenseState").InnerText
  ServerLogTail = if (Test-Path $serverLog) { (Get-Content $serverLog -Tail 5) -join " | " } else { "" }
  PortalLogTail = if (Test-Path $portalLog) { (Get-Content $portalLog -Tail 5) -join " | " } else { "" }
}
