Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverPidFile = Join-Path $scriptRoot "sandbox\runtime\server.pid"
$serverModeFile = Join-Path $scriptRoot "sandbox\runtime\server-mode.txt"
$clientALog = Join-Path $scriptRoot "sandbox\clients\client-a\user-data\DuressText.mdl"
$clientBLog = Join-Path $scriptRoot "sandbox\clients\client-b\user-data\DuressText.mdl"
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$realServerLogDir = Join-Path $programDataRoot "Logs"
$serverMode = if (Test-Path $serverModeFile) { (Get-Content $serverModeFile | Select-Object -First 1) } else { "fake" }
$serverLog = if ($serverMode -eq "real") {
  $latestRealLog = Get-ChildItem -Path $realServerLogDir -Filter "DuressAlert_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($latestRealLog) { $latestRealLog.FullName } else { Join-Path $realServerLogDir ("DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd")) }
} else {
  Join-Path $scriptRoot "sandbox\runtime\server.log"
}

$duress = Get-Process Duress -ErrorAction SilentlyContinue | Sort-Object StartTime
$serverProc = $null
if ($serverMode -eq "fake" -and (Test-Path $serverPidFile)) {
  $pidValue = Get-Content $serverPidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pidValue) {
    $serverProc = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
  }
}
$realService = if ($serverMode -eq "real") { Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue } else { $null }

Write-Host "Processes" -ForegroundColor Cyan
Write-Host "Server mode:" $serverMode
if ($serverMode -eq "real" -and $realService) {
  $realService | Select-Object Name, Status | Format-Table -AutoSize
} elseif ($serverProc) {
  $serverProc | Select-Object Id, ProcessName, StartTime | Format-Table -AutoSize
} else {
  Write-Host "No server process running."
}

if ($duress) {
  $duress | Select-Object Id, ProcessName, StartTime | Format-Table -AutoSize
} else {
  Write-Host "No Duress client processes running."
}

Write-Host ""
Write-Host "Recent server events" -ForegroundColor Cyan
if (Test-Path $serverLog) {
  Get-Content $serverLog | Select-Object -Last 12
} else {
  Write-Host "No server log yet."
}

Write-Host ""
Write-Host "Recent client A log" -ForegroundColor Cyan
if (Test-Path $clientALog) {
  Get-Content $clientALog | Select-Object -Last 8
} else {
  Write-Host "No client A log yet."
}

Write-Host ""
Write-Host "Recent client B log" -ForegroundColor Cyan
if (Test-Path $clientBLog) {
  Get-Content $clientBLog | Select-Object -Last 8
} else {
  Write-Host "No client B log yet."
}
