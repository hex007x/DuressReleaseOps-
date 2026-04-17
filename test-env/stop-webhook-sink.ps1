Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime\webhook-sink"
$pidFile = Join-Path $runtimeRoot "webhook-sink.pid"

if (-not (Test-Path $pidFile)) {
  Write-Host "Webhook sink is not running."
  exit 0
}

$pidValue = Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pidValue) {
  $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $process.Id -Force
  }
}

Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
Write-Host "Stopped local webhook sink."
