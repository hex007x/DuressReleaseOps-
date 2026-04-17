param(
  [switch]$TwoClients,
  [ValidateSet("Fake", "Real")][string]$ServerMode = "Fake"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $scriptRoot "prepare-sandbox.ps1")
& (Join-Path $scriptRoot "build-client.ps1")

if ($ServerMode -eq "Real") {
  & (Join-Path $scriptRoot "build-real-server.ps1")
  & (Join-Path $scriptRoot "start-real-server.ps1")
} else {
  & (Join-Path $scriptRoot "start-server.ps1")
}

& (Join-Path $scriptRoot "run-client.ps1") -ClientId "client-a"

if ($TwoClients) {
  & (Join-Path $scriptRoot "run-client.ps1") -ClientId "client-b"
}

Write-Host ""
Write-Host "Environment is up."
Write-Host "Server mode:" $ServerMode
Write-Host "Inject an alert with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$scriptRoot\inject-message.ps1`""
