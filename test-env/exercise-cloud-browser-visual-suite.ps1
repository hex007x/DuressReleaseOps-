param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\cloud-browser-visual\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$BaseUrl = "http://localhost:5186"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$devSettingsPath = Join-Path $cloudRoot "src\DuressCloud.Web\appsettings.Development.json"
$pythonScript = Join-Path $scriptRoot "cloud-browser-visual-proof.py"
$summaryPath = Join-Path $OutputRoot "CLOUD_BROWSER_VISUAL_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$settings = Get-Content -Path $devSettingsPath -Raw | ConvertFrom-Json
$connectionString = [string]$settings.ConnectionStrings.CloudPlatform
if ([string]::IsNullOrWhiteSpace($connectionString)) {
  throw "Could not find CloudPlatform connection string in $devSettingsPath."
}

$edgePath = Get-ChildItem 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe' -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($edgePath)) {
  throw "Could not locate Microsoft Edge for the browser visual suite."
}

& python $pythonScript --base-url $BaseUrl --output-root $OutputRoot --connection-string $connectionString --edge-path $edgePath
if ($LASTEXITCODE -ne 0) {
  throw "Cloud browser visual suite failed."
}

Write-Host "Cloud browser visual suite written to:" $OutputRoot
Write-Host "Summary:" $summaryPath
