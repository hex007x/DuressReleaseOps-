param(
  [int]$WaitSeconds = 75,
  [string[]]$Modes = @("current", "renewed", "invalid", "error")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$signedLicenseFile = Join-Path $programDataRoot "License.v3.xml"
$runtimeStatusFile = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"
$serverLog = Join-Path $programDataRoot ("Logs\DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$portalLog = Join-Path $scriptRoot "sandbox\runtime\license-portal\license-portal.log"

& (Join-Path $scriptRoot "prepare-license-portal.ps1")
& (Join-Path $scriptRoot "start-license-portal.ps1")
& (Join-Path $scriptRoot "configure-real-server-license-portal.ps1") -CheckHours 1

$results = @()

foreach ($mode in $Modes) {
  & (Join-Path $scriptRoot "set-license-portal-response.ps1") -Mode $mode | Out-Null
  Restart-Service -Name DuressAlertService -Force
  Start-Sleep -Seconds $WaitSeconds

  [xml]$licenseXml = Get-Content $signedLicenseFile
  [xml]$runtimeXml = Get-Content $runtimeStatusFile
  $serverTail = if (Test-Path $serverLog) { (Get-Content $serverLog -Tail 6) -join " | " } else { "" }
  $portalTail = if (Test-Path $portalLog) { (Get-Content $portalLog -Tail 6) -join " | " } else { "" }

  $results += [pscustomobject]@{
    Mode = $mode
    InstalledMaxClients = $licenseXml.SelectSingleNode("/License/MaxClients").InnerText
    InstalledExpiresAtUtc = $licenseXml.SelectSingleNode("/License/ExpiresAtUtc").InnerText
    LastCloudCheckUtc = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudCheckUtc").InnerText
    LastCloudCheckResult = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudCheckResult").InnerText
    LastCloudLicenseState = $runtimeXml.SelectSingleNode("/LicenseRuntimeStatus/LastCloudLicenseState").InnerText
    ServerLogTail = $serverTail
    PortalLogTail = $portalTail
  }
}

$results | Format-Table -AutoSize
