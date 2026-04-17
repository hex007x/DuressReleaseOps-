param(
  [switch]$IncludeProtocolSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$serverLog = Join-Path $programDataRoot ("Logs\DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$runtimeStatusFile = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"

if (-not (Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue) -or
    (Get-Service -Name "DuressAlertService").Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  throw "DuressAlertService must be running."
}

$logBefore = if (Test-Path $serverLog) { @(Get-Content $serverLog) } else { @() }

$protocolResult = $null
if ($IncludeProtocolSmoke) {
  $protocolResult = & (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") -ReceiveTimeoutMs 20000 -StartupDelayMs 1000
}

Start-Sleep -Seconds 2

$logAfter = if (Test-Path $serverLog) { @(Get-Content $serverLog) } else { @() }
$newLog = if ($logAfter.Count -gt $logBefore.Count) { @($logAfter[$logBefore.Count..($logAfter.Count - 1)]) } else { @() }

$licenseLines = @($newLog | Where-Object {
  $_ -match "License renewal warning" -or
  $_ -match "License usage normal" -or
  $_ -match "License usage warning" -or
  $_ -match "License usage grace" -or
  $_ -match "License usage exceeded" -or
  $_ -match "connection declined" -or
  $_ -match "declined:"
})

$runtimeStatus = $null
if (Test-Path $runtimeStatusFile) {
  [xml]$runtimeStatus = Get-Content $runtimeStatusFile
}

[pscustomobject]@{
  Suite = "Licensing"
  RuntimeStatusFile = $runtimeStatusFile
  CurrentClients = if ($runtimeStatus) { $runtimeStatus.LicenseRuntimeStatus.CurrentConnectedClients } else { "" }
  GraceLimit = if ($runtimeStatus) { $runtimeStatus.LicenseRuntimeStatus.GraceClientLimit } else { "" }
  LastCloudCheck = if ($runtimeStatus) { $runtimeStatus.LicenseRuntimeStatus.LastCloudCheckUtc } else { "" }
  LastCloudResult = if ($runtimeStatus) { $runtimeStatus.LicenseRuntimeStatus.LastCloudCheckResult } else { "" }
  LicenseLines = $licenseLines
  ProtocolSmokeIncluded = [bool]$IncludeProtocolSmoke
  ProtocolSmoke = $protocolResult
} | Format-List
