<#
.SYNOPSIS
Closes visible Duress/MSI test windows left behind by local regression runs.

.DESCRIPTION
Finds visible top-level windows for known Duress test processes and asks them to
close cleanly before forcing termination if needed. This intentionally avoids
background or service-only processes by only targeting processes that have a
main window handle.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\close-visible-test-windows.ps1

.NOTES
Script version: 2026.04.14.1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$targetNames = @("Duress", "DuressServer", "msiexec")
$closed = New-Object System.Collections.Generic.List[string]

function Stop-VisibleProcess {
  param(
    [Parameter(Mandatory = $true)]$Process
  )

  if ($Process.MainWindowHandle -eq 0) {
    return
  }

  $label = "{0} ({1})" -f $Process.ProcessName, $Process.Id
  if (-not $PSCmdlet.ShouldProcess($label, "Close visible test window")) {
    return
  }

  try {
    $null = $Process.CloseMainWindow()
  }
  catch {}

  try {
    if (-not $Process.WaitForExit(3000)) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
  }
  catch {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
  }

  $closed.Add($label) | Out-Null
}

$visibleTargets = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -in $targetNames -and $_.MainWindowHandle -ne 0 }

foreach ($process in $visibleTargets) {
  Stop-VisibleProcess -Process $process
}

$testEnvRoot = (Resolve-Path (Join-Path $PSScriptRoot ".")).Path
$shellCandidates = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -in @("powershell.exe", "pwsh.exe") -and
    $_.CommandLine -and
    $_.CommandLine -like "*$testEnvRoot*"
  }

foreach ($candidate in $shellCandidates) {
  try {
    $process = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
    if ($process) {
      if ($process.MainWindowHandle -ne 0) {
        Stop-VisibleProcess -Process $process
      }
      else {
        $label = "{0} ({1})" -f $process.ProcessName, $process.Id
        if ($PSCmdlet.ShouldProcess($label, "Stop headless test helper shell")) {
          Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
          $closed.Add($label) | Out-Null
        }
      }
    }
  }
  catch {}
}

if ($closed.Count -eq 0) {
  Write-Host "No visible Duress/MSI test windows were left open."
}
else {
  Write-Host "Closed visible test windows:"
  $closed | Sort-Object | ForEach-Object { Write-Host "- $_" }
}
