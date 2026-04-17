param(
  [int]$ReceiveTimeoutMs = 20000,
  [int]$StartupDelayMs = 1000,
  [switch]$IncludeNotifications
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$serverLog = Join-Path $programDataRoot ("Logs\DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$auditLog = Get-ChildItem -Path (Join-Path $programDataRoot "Audit") -Filter "DuressAudit_*.log" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not (Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue) -or
    (Get-Service -Name "DuressAlertService").Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  throw "DuressAlertService must be running."
}

$logBefore = @(if (Test-Path $serverLog) { Get-Content $serverLog } else { @() })
$auditBefore = @(if ($auditLog) { Get-Content $auditLog.FullName } else { @() })

$protocolResult = & (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") -ReceiveTimeoutMs $ReceiveTimeoutMs -StartupDelayMs $StartupDelayMs
Start-Sleep -Seconds 3

$logAfter = @(if (Test-Path $serverLog) { Get-Content $serverLog } else { @() })
$auditLog = Get-ChildItem -Path (Join-Path $programDataRoot "Audit") -Filter "DuressAudit_*.log" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
$auditAfter = @(if ($auditLog) { Get-Content $auditLog.FullName } else { @() })

$newLog = if ($logAfter.Count -gt $logBefore.Count) { @($logAfter[$logBefore.Count..($logAfter.Count - 1)]) } else { @() }
$newAudit = if ($auditAfter.Count -gt $auditBefore.Count) { @($auditAfter[$auditBefore.Count..($auditAfter.Count - 1)]) } else { @() }

$notificationLines = @($newLog | Where-Object {
  $_ -match "notification sent for ALERT" -or
  $_ -match "notification sent for RESPONSE" -or
  $_ -match "notification sent for RESET"
})

$result = [pscustomobject]@{
  Suite = "Incident"
  Protocol = $protocolResult
  ServerLog = $serverLog
  AuditLog = if ($auditLog) { $auditLog.FullName } else { "" }
  NotificationLines = $notificationLines
  AuditLines = $newAudit
}

if ($IncludeNotifications) {
  $result | Format-List
} else {
  [pscustomobject]@{
    Suite = "Incident"
    AlertSent = $protocolResult.AlertSent
    AlertReceivedByB = $protocolResult.AlertReceivedByB
    ResponseSent = $protocolResult.ResponseSent
    ResponseReceivedByA = $protocolResult.ResponseReceivedByA
    ResetSent = $protocolResult.AckSent
    ResetReceivedByB = $protocolResult.AckReceivedByB
    NotificationLines = @($notificationLines).Count
  } | Format-List
}
