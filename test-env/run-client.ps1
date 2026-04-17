param(
  [string]$ClientId = "client-a"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $scriptRoot "build-client.ps1"
$prepareScript = Join-Path $scriptRoot "prepare-sandbox.ps1"
$buildRoot = Join-Path $scriptRoot "build"
$releasesRoot = Join-Path $buildRoot "releases"
$latestPointer = Join-Path $buildRoot "latest-build.txt"
$userRoot = Join-Path $scriptRoot ("sandbox\clients\" + $ClientId + "\user-data")
$commonRoot = Join-Path $scriptRoot "sandbox\common-data"

& $prepareScript

function Get-LatestClientExePath {
  if (Test-Path $latestPointer) {
    $latestBuild = (Get-Content $latestPointer -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($latestBuild) {
      $candidate = Join-Path $releasesRoot $latestBuild
      $candidateExe = Join-Path $candidate "Duress.exe"
      if (Test-Path $candidateExe) {
        return $candidateExe
      }
    }
  }

  if (Test-Path $releasesRoot) {
    $latestDir = Get-ChildItem -Path $releasesRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latestDir) {
      $candidateExe = Join-Path $latestDir.FullName "Duress.exe"
      if (Test-Path $candidateExe) {
        return $candidateExe
      }
    }
  }

  return $null
}

$exePath = Get-LatestClientExePath
if (-not $exePath) {
  & $buildScript
  $exePath = Get-LatestClientExePath
}

if (-not $exePath) {
  throw "Could not find a built client executable."
}

if (-not (Test-Path $userRoot)) {
  throw "Unknown client sandbox '$ClientId'."
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exePath
$psi.WorkingDirectory = Split-Path -Parent $exePath
$psi.UseShellExecute = $false
$psi.EnvironmentVariables["DURESS_USER_DATA_ROOT"] = $userRoot
$psi.EnvironmentVariables["DURESS_COMMON_DATA_ROOT"] = $commonRoot
$psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
$psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = $ClientId

$process = [System.Diagnostics.Process]::Start($psi)
Write-Host "Started client PID $($process.Id)"
Write-Host "Client sandbox     :" $ClientId
Write-Host "Sandbox user data :" $userRoot
Write-Host "Sandbox common data:" $commonRoot
