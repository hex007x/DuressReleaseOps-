Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sinkLog = Join-Path $scriptRoot "sandbox\runtime\webhook-sink\webhook-sink.log"
$serverLog = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert\Logs\DuressAlert_$(Get-Date -Format 'yyyyMMdd').log"

if (-not (Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue) -or
    (Get-Service -Name "DuressAlertService").Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  throw "DuressAlertService must be running."
}

$sinkBefore = if (Test-Path $sinkLog) { @(Get-Content $sinkLog) } else { @() }
$serverBefore = if (Test-Path $serverLog) { @(Get-Content $serverLog) } else { @() }

& (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") | Out-Null
Start-Sleep -Seconds 2

$sinkAfter = if (Test-Path $sinkLog) { @(Get-Content $sinkLog) } else { @() }
$serverAfter = if (Test-Path $serverLog) { @(Get-Content $serverLog) } else { @() }

[pscustomobject]@{
  NewSinkEntries = ($sinkAfter | Select-Object -Skip $sinkBefore.Count)
  NewServerLogEntries = ($serverAfter | Select-Object -Skip $serverBefore.Count | Where-Object {
      $_ -match 'Slack notification sent|Teams notification sent|Google Chat notification sent'
    })
} | Format-List
