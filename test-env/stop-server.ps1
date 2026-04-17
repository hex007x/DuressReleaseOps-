Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $scriptRoot "sandbox\runtime\server.pid"

if (-not (Test-Path $pidFile)) {
  Write-Host "Server is not running."
  exit 0
}

$pidValue = Get-Content $pidFile | Select-Object -First 1
if ($pidValue) {
  try {
    Stop-Process -Id ([int]$pidValue) -Force -ErrorAction Stop
    Write-Host "Stopped fake server PID $pidValue"
  } catch {
    Write-Host "Server process was not running."
  }
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
