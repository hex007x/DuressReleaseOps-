Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portalRoot = Join-Path $scriptRoot "sandbox\runtime\license-portal"
$pidFile = Join-Path $portalRoot "license-portal.pid"

if (-not (Test-Path $pidFile)) {
  Write-Host "License portal is not running."
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
Write-Host "Stopped local license portal."
