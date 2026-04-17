Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$logFile = Get-ChildItem -Path (Join-Path $programDataRoot "Logs") -Filter "DuressAlert_*.log" |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $logFile) {
  throw "No server log file found under $programDataRoot\\Logs"
}

$before = @(Get-Content $logFile.FullName)

& (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") | Out-Null

Start-Sleep -Seconds 3

$after = @(Get-Content $logFile.FullName)
$newLines = @()
if ($after.Count -gt $before.Count) {
  $newLines = $after[$before.Count..($after.Count - 1)]
}

$matches = @($newLines | Where-Object {
  $_ -match "notification sent" -or $_ -match "notification attempt" -or $_ -match "Alert email sent"
})

[pscustomobject]@{
  LogFile = $logFile.FullName
  MatchingLines = $matches.Count
}

if ($matches.Count -gt 0) {
  $matches
} else {
  Write-Warning "No email notification lines were found in the new server log output."
}
