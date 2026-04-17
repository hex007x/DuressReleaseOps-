Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptRoot "run-client.ps1") -ClientId "client-a"
Start-Sleep -Seconds 1
& (Join-Path $scriptRoot "run-client.ps1") -ClientId "client-b"
