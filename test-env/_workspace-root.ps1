Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DuressReleaseOpsRoot {
  param(
    [string]$ScriptRoot = $PSScriptRoot
  )

  return (Resolve-Path (Join-Path $ScriptRoot "..")).Path
}

function Get-DuressWorkspaceRoot {
  param(
    [string]$ScriptRoot = $PSScriptRoot
  )

  $repoRoot = Get-DuressReleaseOpsRoot -ScriptRoot $ScriptRoot
  return (Resolve-Path (Join-Path $repoRoot "..")).Path
}
