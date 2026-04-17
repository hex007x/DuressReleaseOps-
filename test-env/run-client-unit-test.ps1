Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$projectPath = Join-Path $workspaceRoot "Duress2025\Duress2025.Tests\Duress2025.Tests.csproj"
$exePath = Join-Path $workspaceRoot "Duress2025\Duress2025.Tests\bin\Release\Duress2025.Tests.exe"
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

& $msbuild $projectPath /t:Build /p:Configuration=Release /p:Platform="AnyCPU"
if ($LASTEXITCODE -ne 0) {
  throw "Client unit test project compilation failed via MSBuild."
}

if (-not (Test-Path $exePath)) {
  throw "Could not find built client unit test executable at $exePath"
}

& $exePath
if ($LASTEXITCODE -ne 0) {
  throw "Client unit tests failed."
}
