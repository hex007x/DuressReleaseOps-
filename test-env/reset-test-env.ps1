Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sandboxRoot = Join-Path $scriptRoot "sandbox"
$buildRoot = Join-Path $scriptRoot "build"
$serverBuildRoot = Join-Path $scriptRoot "server-build"
$serverPidFile = Join-Path $sandboxRoot "runtime\server.pid"
$serverModeFile = Join-Path $sandboxRoot "runtime\server-mode.txt"

Get-Process Duress -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
try {
  cmd /c "taskkill /IM Duress.exe /F" *> $null
} catch {
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -eq 'powershell.exe' -and
    $_.CommandLine -match 'Duress Fake Server Log|Duress Real Server Log|Duress Client A Log|Duress Client B Log'
  } |
  ForEach-Object {
    try {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    } catch {
    }
  }

if (Test-Path $serverPidFile) {
  & (Join-Path $scriptRoot "stop-server.ps1")
}

if (Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue) {
  & (Join-Path $scriptRoot "uninstall-real-server-v2.ps1")
}

if (Test-Path $sandboxRoot) {
  Get-ChildItem $sandboxRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('DuressText.mdl', 'server.log', 'server.pid', 'server-mode.txt', 'pos.data') } |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

if (Test-Path $buildRoot) {
  Get-ChildItem $buildRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('Duress.exe', 'Duress.exe.config', 'Duress.pdb') } |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

if (Test-Path $serverBuildRoot) {
  Get-ChildItem $serverBuildRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('DuressServer.exe', 'DuressServer.exe.config', 'DuressServer.pdb') } |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

& (Join-Path $scriptRoot "prepare-sandbox.ps1")

Write-Host "Reset complete."
Write-Host "Clients stopped, server stopped, runtime logs cleared, sandboxes re-seeded."
