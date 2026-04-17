Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$serverModeFile = Join-Path $runtimeRoot "server-mode.txt"
$serverMode = if (Test-Path $serverModeFile) { (Get-Content $serverModeFile | Select-Object -First 1) } else { "fake" }
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$realServerLogDir = Join-Path $programDataRoot "Logs"
$realServerLog = Get-ChildItem -Path $realServerLogDir -Filter "DuressAlert_*.log" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

function Start-TailWindow {
  param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Color
  )

  $tailScript = @"
`$Host.UI.RawUI.WindowTitle = '$Title'
Write-Host '$Title' -ForegroundColor $Color
Write-Host 'Watching: $Path' -ForegroundColor $Color
if (-not (Test-Path '$Path')) {
  New-Item -ItemType File -Force -Path '$Path' | Out-Null
}
Get-Content '$Path' -Wait
"@

  Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy", "Bypass",
    "-Command", $tailScript
  ) | Out-Null
}

if ($serverMode -eq "real") {
  $realLogPath = if ($realServerLog) { $realServerLog.FullName } else { Join-Path $realServerLogDir ("DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd")) }
  Start-TailWindow -Title "Duress Real Server Log" -Path $realLogPath -Color "Cyan"
} else {
  Start-TailWindow -Title "Duress Fake Server Log" -Path (Join-Path $scriptRoot "sandbox\runtime\server.log") -Color "Cyan"
}

Start-TailWindow -Title "Duress Client A Log" -Path (Join-Path $scriptRoot "sandbox\clients\client-a\user-data\DuressText.mdl") -Color "Green"
Start-TailWindow -Title "Duress Client B Log" -Path (Join-Path $scriptRoot "sandbox\clients\client-b\user-data\DuressText.mdl") -Color "Yellow"

Write-Host "Opened monitor windows for server, client A, and client B logs."
Write-Host "Run '.\\test-env\\show-status.ps1' anytime for a quick snapshot in this console."
