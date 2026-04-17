Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $scriptRoot "sandbox\runtime\legacy-wire-server.pid"

if (-not (Test-Path $pidFile)) {
  Write-Host "Legacy wire server is not running."
  exit 0
}

$pidValue = Get-Content $pidFile | Select-Object -First 1
if ($pidValue) {
  try {
    Stop-Process -Id ([int]$pidValue) -Force -ErrorAction Stop
    Write-Host "Stopped legacy wire server PID $pidValue"
  } catch {
    Write-Host "Legacy wire server process was not running."
  }
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
