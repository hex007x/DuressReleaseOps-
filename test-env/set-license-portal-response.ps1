param(
  [ValidateSet("current", "renewed", "invalid", "error")][string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portalRoot = Join-Path $scriptRoot "sandbox\runtime\license-portal"
$activeModeFile = Join-Path $portalRoot "active-mode.txt"

New-Item -ItemType Directory -Force -Path $portalRoot | Out-Null
Set-Content -Path $activeModeFile -Value $Mode -Encoding ASCII

Write-Host "Local license portal mode set to:" $Mode
