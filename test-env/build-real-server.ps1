Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$projectPath = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\DuressServer2025.csproj"
$buildRoot = Join-Path $scriptRoot "server-build"
$serviceName = "DuressAlertService"

function Stop-ServiceIfRunning {
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  if (-not $service) {
    return $false
  }

  if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
    Write-Host "Stopping real server service so the build output can be refreshed..."
    Stop-Service -Name $serviceName
    $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20))
    return $true
  }

  return $false
}

function Stop-BuildOutputProcesses {
  $targetPath = (Join-Path $buildRoot "DuressServer.exe")
  $processes = @(
    Get-Process -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Path -eq $targetPath -or
        ($_.ProcessName -eq "DuressServer" -and $_.Path -like "$buildRoot*")
      }
  )

  foreach ($process in $processes) {
    try {
      Stop-Process -Id $process.Id -Force -ErrorAction Stop
    }
    catch {
    }
  }
}

function Copy-WithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  try {
    Copy-Item $Source $Destination -Force
  } catch [System.IO.IOException] {
    $stopped = Stop-ServiceIfRunning
    Stop-BuildOutputProcesses
    if (-not $stopped) {
      throw
    }

    Start-Sleep -Seconds 1
    Copy-Item $Source $Destination -Force
  }
}

$vsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = $null

if (Test-Path $vsWhere) {
  $installPath = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
  if ($installPath) {
    $candidate = Join-Path $installPath "MSBuild\Current\Bin\MSBuild.exe"
    if (Test-Path $candidate) {
      $msbuild = $candidate
    }
  }
}

if (-not $msbuild) {
  throw "Could not find Visual Studio Build Tools MSBuild. Install VS 2022 Build Tools first."
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

& $msbuild $projectPath /t:Build /p:Configuration=Release /p:Platform="AnyCPU"
if ($LASTEXITCODE -ne 0) {
  throw "Server compilation failed via MSBuild."
}

$releaseRoot = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\bin\Release"
Copy-WithRetry (Join-Path $releaseRoot "DuressServer.exe") (Join-Path $buildRoot "DuressServer.exe")
Copy-WithRetry (Join-Path $releaseRoot "DuressServer.exe.config") (Join-Path $buildRoot "DuressServer.exe.config")

if (Test-Path (Join-Path $releaseRoot "DuressServer.pdb")) {
  Copy-WithRetry (Join-Path $releaseRoot "DuressServer.pdb") (Join-Path $buildRoot "DuressServer.pdb")
}

Write-Host "Built real server:" (Join-Path $buildRoot "DuressServer.exe")
