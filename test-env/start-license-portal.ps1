param(
  [int]$Port = 8055,
  [string]$Token = "local-test-token"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portalRoot = Join-Path $scriptRoot "sandbox\runtime\license-portal"
$pidFile = Join-Path $portalRoot "license-portal.pid"

New-Item -ItemType Directory -Force -Path $portalRoot | Out-Null

if (-not (Test-Path (Join-Path $portalRoot "current-license.xml"))) {
  & (Join-Path $scriptRoot "prepare-license-portal.ps1")
}

if (Test-Path $pidFile) {
  $existingPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($existingPid) {
    $existingProcess = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existingProcess) {
      Write-Host "License portal already running as PID $existingPid"
      return
    }
  }
}

$env:DURESS_LICENSE_PORTAL_PORT = $Port.ToString()
$env:DURESS_LICENSE_PORTAL_TOKEN = $Token

$process = Start-Process python `
  -ArgumentList @((Join-Path $scriptRoot "local_license_portal.py")) `
  -PassThru `
  -WorkingDirectory $scriptRoot `
  -WindowStyle Hidden

Set-Content -Path $pidFile -Value $process.Id -Encoding ASCII

Write-Host "Started local license portal:"
Write-Host "  URL   : http://127.0.0.1:$Port/licenses/check-in"
Write-Host "  Token : $Token"
Write-Host "  PID   :" $process.Id
