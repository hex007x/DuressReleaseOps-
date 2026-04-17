param(
  [int]$Port = 8011
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$pidFile = Join-Path $runtimeRoot "legacy-wire-server.pid"
$logFile = Join-Path $runtimeRoot "legacy-wire-server.log"

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (Test-Path $pidFile) {
  $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($oldPid) {
    try {
      $existing = Get-Process -Id ([int]$oldPid) -ErrorAction Stop
      Write-Host "Legacy wire server already running with PID $($existing.Id)"
      exit 0
    } catch {
    }
  }
}

$python = (Get-Command python -ErrorAction Stop).Source
$serverScript = Join-Path $scriptRoot "legacy_wire_server.py"
$process = Start-Process -FilePath $python -ArgumentList @(
  $serverScript,
  "--port", $Port,
  "--log", $logFile
) -PassThru -WindowStyle Hidden

Set-Content -Path $pidFile -Value $process.Id

Write-Host "Started legacy wire server PID $($process.Id)"
Write-Host "Port:" $Port
Write-Host "Log :" $logFile
