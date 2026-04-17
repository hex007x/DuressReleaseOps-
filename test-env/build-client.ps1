Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$projectPath = Join-Path $workspaceRoot "Duress2025\Duress\Duress.csproj"
$buildRoot = Join-Path $scriptRoot "build"
$releasesRoot = Join-Path $buildRoot "releases"
$latestPointer = Join-Path $buildRoot "latest-build.txt"

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

New-Item -ItemType Directory -Force -Path $buildRoot, $releasesRoot | Out-Null

& $msbuild $projectPath /t:Build /p:Configuration=Release /p:Platform="AnyCPU"
if ($LASTEXITCODE -ne 0) {
  throw "Client compilation failed via MSBuild."
}

$releaseRoot = Join-Path $workspaceRoot "Duress2025\Duress\bin\Release"
$buildStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputRoot = Join-Path $releasesRoot $buildStamp
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

Copy-Item (Join-Path $releaseRoot "Duress.exe") (Join-Path $outputRoot "Duress.exe") -Force
Copy-Item (Join-Path $releaseRoot "Duress.exe.config") (Join-Path $outputRoot "Duress.exe.config") -Force
Copy-Item (Join-Path $releaseRoot "Newtonsoft.Json.dll") (Join-Path $outputRoot "Newtonsoft.Json.dll") -Force

if (Test-Path (Join-Path $releaseRoot "Duress.pdb")) {
  Copy-Item (Join-Path $releaseRoot "Duress.pdb") (Join-Path $outputRoot "Duress.pdb") -Force
}

Set-Content -Path $latestPointer -Value $buildStamp -Encoding ASCII

Write-Host "Built test client:" (Join-Path $outputRoot "Duress.exe")
