param(
  [int]$Port = 8065
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime\webhook-sink"
$pidFile = Join-Path $runtimeRoot "webhook-sink.pid"

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (Test-Path $pidFile) {
  $existingPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($existingPid) {
    $existingProcess = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existingProcess) {
      Write-Host "Webhook sink already running as PID $existingPid"
      return
    }
  }
}

$env:DURESS_WEBHOOK_SINK_PORT = $Port.ToString()
$process = Start-Process python `
  -ArgumentList @((Join-Path $scriptRoot "local_webhook_sink.py")) `
  -PassThru `
  -WorkingDirectory $scriptRoot `
  -WindowStyle Hidden

Set-Content -Path $pidFile -Value $process.Id -Encoding ASCII

Write-Host "Started local webhook sink:"
Write-Host "  Base URL: http://127.0.0.1:$Port"
Write-Host "  PID     :" $process.Id
