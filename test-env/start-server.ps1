param(
  [Nullable[Int64]]$MaxBytes = $null,
  [Nullable[Int]]$BackupCount = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$pidFile = Join-Path $runtimeRoot "server.pid"
$logFile = Join-Path $runtimeRoot "server.log"
$maxBytes = if ($MaxBytes -ne $null) { $MaxBytes } elseif ($env:DURESS_SERVER_LOG_MAX_BYTES) { [int64]$env:DURESS_SERVER_LOG_MAX_BYTES } else { 10MB }
$backupCount = if ($BackupCount -ne $null) { $BackupCount } elseif ($env:DURESS_SERVER_LOG_BACKUP_COUNT) { [int]$env:DURESS_SERVER_LOG_BACKUP_COUNT } else { 5 }

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (Test-Path $pidFile) {
  $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue
  if ($oldPid) {
    try {
      $existing = Get-Process -Id ([int]$oldPid) -ErrorAction Stop
      Write-Host "Server already running with PID $($existing.Id)"
      exit 0
    } catch {
    }
  }
}

$python = (Get-Command python -ErrorAction Stop).Source
$serverScript = Join-Path $scriptRoot "fake_duress_server.py"
$process = Start-Process -FilePath $python -ArgumentList @(
  $serverScript,
  "--log", $logFile,
  "--max-bytes", $maxBytes,
  "--backup-count", $backupCount
) -PassThru -WindowStyle Hidden
Set-Content -Path $pidFile -Value $process.Id

Write-Host "Started fake server PID $($process.Id)"
Write-Host "Log:" $logFile
Write-Host "Max bytes:" $maxBytes
Write-Host "Backup count:" $backupCount
