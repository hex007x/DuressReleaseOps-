param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\cloud-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$BaseUrl = "http://localhost:5186"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$unitTestsProject = Join-Path $cloudRoot "tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj"
$integrationTestsProject = Join-Path $cloudRoot "tests\DuressCloud.Web.IntegrationTests\DuressCloud.Web.IntegrationTests.csproj"
$webProject = Join-Path $cloudRoot "src\DuressCloud.Web\DuressCloud.Web.csproj"
$cloudAuthSmokeScript = Join-Path $scriptRoot "exercise-cloud-auth-smoke.ps1"
$logsRoot = Join-Path $OutputRoot "logs"
$publishRoot = Join-Path $OutputRoot "publish"
$summaryPath = Join-Path $OutputRoot "CLOUD_REGRESSION_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $publishRoot | Out-Null

function Invoke-And-Capture {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  $logPath = Join-Path $logsRoot ($Name + ".log")
  Write-Host "Running:" $Name
  try {
    $output = & $Action 2>&1 | Tee-Object -FilePath $logPath
    return [pscustomobject]@{
      Name = $Name
      Success = $true
      LogPath = $logPath
      Output = ($output | Out-String)
    }
  }
  catch {
    $_ | Out-String | Tee-Object -FilePath $logPath -Append | Out-Null
    return [pscustomobject]@{
      Name = $Name
      Success = $false
      LogPath = $logPath
      Output = (Get-Content $logPath -Raw)
    }
  }
}

function Test-LiveEndpoint {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$ExpectedStatusCode = 200
  )

  $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction Stop
  if ($response.StatusCode -ne $ExpectedStatusCode) {
    throw "Expected status $ExpectedStatusCode from $Url but received $($response.StatusCode)."
  }

  return $response
}

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "01-cloud-unit-tests" -Action {
  & dotnet test $unitTestsProject --configuration Release --nologo
  if ($LASTEXITCODE -ne 0) {
    throw "Cloud unit tests failed."
  }
}))

$results.Add((Invoke-And-Capture -Name "02-cloud-integration-tests" -Action {
  & dotnet test $integrationTestsProject --configuration Release --nologo
  if ($LASTEXITCODE -ne 0) {
    throw "Cloud integration tests failed."
  }
}))

$results.Add((Invoke-And-Capture -Name "03-cloud-publish" -Action {
  & dotnet publish $webProject --configuration Release --output $publishRoot --nologo
  if ($LASTEXITCODE -ne 0) {
    throw "Cloud publish failed."
  }

  $publishedExe = Join-Path $publishRoot "DuressCloud.Web.exe"
  $publishedDll = Join-Path $publishRoot "DuressCloud.Web.dll"
  if (-not (Test-Path $publishedExe) -and -not (Test-Path $publishedDll)) {
    throw "Cloud publish output did not include DuressCloud.Web executable or DLL."
  }

  "Publish output: $publishRoot"
}))

$readyUrl = ($BaseUrl.TrimEnd('/') + "/ready")
$healthUrl = ($BaseUrl.TrimEnd('/') + "/health")
$managementLoginUrl = ($BaseUrl.TrimEnd('/') + "/Management/Login")
$portalLoginUrl = ($BaseUrl.TrimEnd('/') + "/Portal/Login")

$results.Add((Invoke-And-Capture -Name "04-live-cloud-smoke" -Action {
  try {
    $ready = Test-LiveEndpoint -Url $readyUrl -ExpectedStatusCode 200
    $health = Test-LiveEndpoint -Url $healthUrl -ExpectedStatusCode 200
    $management = Test-LiveEndpoint -Url $managementLoginUrl -ExpectedStatusCode 200
    $portal = Test-LiveEndpoint -Url $portalLoginUrl -ExpectedStatusCode 200
  }
  catch {
    throw "Live cloud smoke failed at base URL $BaseUrl. $($_.Exception.Message)"
  }

  [pscustomobject]@{
    Ready = $ready.StatusCode
    Health = $health.StatusCode
    ManagementLogin = $management.StatusCode
    PortalLogin = $portal.StatusCode
  } | Format-List
}))

$results.Add((Invoke-And-Capture -Name "05-cloud-auth-smoke" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $cloudAuthSmokeScript -OutputRoot (Join-Path $OutputRoot "auth-smoke") -BaseUrl $BaseUrl
}))

$summary = @()
$summary += "# Cloud Regression Suite"
$summary += ""
$summary += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summary += ""
$summary += "## Coverage"
$summary += ""
$summary += "- Cloud unit tests"
$summary += "- Cloud integration tests"
$summary += "- Release publish validation"
$summary += "- Live cloud ready/health/login smoke against $BaseUrl"
$summary += "- Authenticated management and portal smoke with MFA completion and portal MSI download"
$summary += ""
$summary += "## Results"
$summary += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $summary += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$summary += ""
$summary += "## Publish Output"
$summary += ""
$summary += "- [$publishRoot]($($publishRoot -replace '\\','/'))"
$summary += ""
$summary += "## Notes"
$summary += ""
$summary += "- This suite is intended to catch cloud-side regressions before release candidates are promoted."
$summary += "- The live smoke expects the local dev/test cloud site to be reachable at the configured base URL."

Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Cloud regression suite written to:" $OutputRoot
Write-Host "Summary:" $summaryPath

if ($failed.Count -gt 0) {
  throw ("Cloud regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
