param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\full-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [switch]$IncludeRealService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$clientUnitScript = Join-Path $scriptRoot "run-client-unit-test.ps1"
$clientConfigModesScript = Join-Path $scriptRoot "verify-client-config-modes.ps1"
$clientUninstallScript = Join-Path $scriptRoot "verify-client-uninstall-config-preservation.ps1"
$clientRuntimeScript = Join-Path $scriptRoot "verify-windows-client-runtime.ps1"
$serverTestsProject = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025.Tests\DuressServer2025.Tests.csproj"
$serverTestsExe = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025.Tests\bin\Release\DuressServer2025.Tests.exe"
$cloudRegressionScript = Join-Path $scriptRoot "exercise-cloud-regression-suite.ps1"
$customerOnboardingRegressionScript = Join-Path $scriptRoot "exercise-customer-onboarding-regression-suite.ps1"
$knownIssueRegressionScript = Join-Path $scriptRoot "exercise-known-issue-regression-suite.ps1"
$commercialRegressionScript = Join-Path $scriptRoot "exercise-commercial-regression-suite.ps1"
$msiUpgradeMetadataScript = Join-Path $scriptRoot "exercise-msi-upgrade-metadata-suite.ps1"
$policySuiteScript = Join-Path $scriptRoot "exercise-client-policy-suite.ps1"
$compatSuiteScript = Join-Path $scriptRoot "exercise-compatibility-suite.ps1"
$incidentSuiteScript = Join-Path $scriptRoot "exercise-incident-suite.ps1"
$licensingSuiteScript = Join-Path $scriptRoot "exercise-licensing-suite.ps1"
$linkedCloudSuiteScript = Join-Path $scriptRoot "exercise-linked-cloud-regression-suite.ps1"
$visualDemoScript = Join-Path $scriptRoot "run-visual-demo.ps1"
$monitorShotScript = Join-Path $scriptRoot "capture-monitor-screenshot.ps1"
$stopFakeServerScript = Join-Path $scriptRoot "stop-server.ps1"
$startRealServerScript = Join-Path $scriptRoot "start-real-server.ps1"
$closeWindowsScript = Join-Path $scriptRoot "close-visible-test-windows.ps1"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"

$logsRoot = Join-Path $OutputRoot "logs"
$shotsRoot = Join-Path $OutputRoot "screenshots"
New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $shotsRoot | Out-Null

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

function Ensure-RealServiceRunning {
  $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if (-not $service) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $startRealServerScript | Out-Null
    $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
    if (-not $service) {
      throw "DuressAlertService is not installed."
    }
  }

  if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
    Start-Service -Name "DuressAlertService"
    Start-Sleep -Seconds 4
    $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
      throw "DuressAlertService did not start successfully."
    }
  }
}

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "00-client-config-modes" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $clientConfigModesScript
}))

$results.Add((Invoke-And-Capture -Name "00b-client-uninstall-config-preservation" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $clientUninstallScript
}))

$results.Add((Invoke-And-Capture -Name "00c-client-runtime" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $clientRuntimeScript
}))

$results.Add((Invoke-And-Capture -Name "01-client-unit-tests" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $clientUnitScript
}))

$results.Add((Invoke-And-Capture -Name "02-server-unit-tests" -Action {
  & $msbuild (Join-Path $workspaceRoot "_external\\DuressServer2025\\DuressServer2025\\DuressServer2025.csproj") /t:Build /p:Configuration=Release /p:Platform=AnyCPU
  if ($LASTEXITCODE -ne 0) { throw "Server project build failed." }
  & $msbuild $serverTestsProject /t:Build /p:Configuration=Release /p:Platform=AnyCPU /p:BuildProjectReferences=false
  if ($LASTEXITCODE -ne 0) { throw "Server test build failed." }
  & $serverTestsExe
}))

$results.Add((Invoke-And-Capture -Name "02b-cloud-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $cloudRegressionScript
}))

$results.Add((Invoke-And-Capture -Name "02c-customer-onboarding-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $customerOnboardingRegressionScript
}))

$results.Add((Invoke-And-Capture -Name "02d-known-issue-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $knownIssueRegressionScript
}))

$results.Add((Invoke-And-Capture -Name "02e-commercial-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $commercialRegressionScript
}))

$results.Add((Invoke-And-Capture -Name "02f-msi-upgrade-metadata-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $msiUpgradeMetadataScript
}))

$results.Add((Invoke-And-Capture -Name "03-policy-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $policySuiteScript
}))

$compatibilityName = "04-compatibility-suite"
if ($IncludeRealService) {
  $results.Add((Invoke-And-Capture -Name "03b-real-service-ready-for-compat" -Action {
    Ensure-RealServiceRunning
    "DuressAlertService is running for compatibility coverage."
  }))
}

$results.Add((Invoke-And-Capture -Name $compatibilityName -Action {
  if ($IncludeRealService) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $compatSuiteScript -IncludeRealService
  }
  else {
    powershell -NoProfile -ExecutionPolicy Bypass -File $compatSuiteScript
  }
}))

if ($IncludeRealService) {
  $results.Add((Invoke-And-Capture -Name "05-real-service-ready" -Action {
    Ensure-RealServiceRunning
    "DuressAlertService is running."
  }))
}

$service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
  $results.Add((Invoke-And-Capture -Name "05-incident-suite" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $incidentSuiteScript -IncludeNotifications
  }))
  $results.Add((Invoke-And-Capture -Name "06-licensing-suite" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $licensingSuiteScript -IncludeProtocolSmoke
  }))
  $results.Add((Invoke-And-Capture -Name "06b-linked-cloud-regression-suite" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $linkedCloudSuiteScript
  }))
}
else {
  $skipLog = Join-Path $logsRoot "05-real-service-skipped.log"
  "DuressAlertService was not running, so the incident, licensing, and linked-cloud real-service suites were skipped." | Set-Content -Path $skipLog
  $results.Add([pscustomobject]@{
    Name = "05-real-service-suites-skipped"
    Success = $true
    LogPath = $skipLog
    Output = Get-Content $skipLog -Raw
  })
}

$results.Add((Invoke-And-Capture -Name "07-visual-demo" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $visualDemoScript -OutputRoot $shotsRoot
}))

$results.Add((Invoke-And-Capture -Name "07b-visual-demo-cleanup" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $stopFakeServerScript
}))

$results.Add((Invoke-And-Capture -Name "08-monitor-screenshot" -Action {
  $policyServerRoot = Join-Path $scriptRoot "sandbox\policy-suite\server-data"
  powershell -NoProfile -ExecutionPolicy Bypass -File $monitorShotScript -OutputPath (Join-Path $shotsRoot "server-monitor-policy.png") -ServerDataRoot $policyServerRoot
}))

$summaryPath = Join-Path $OutputRoot "REGRESSION_SUMMARY.md"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$summary = @()
$summary += "# Full Regression Pack"
$summary += ""
$summary += "Generated: $timestamp"
$summary += ""
$summary += "## Results"
$summary += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $summary += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$summary += ""
$summary += "## Screenshots"
$summary += ""
$shots = Get-ChildItem -Path $shotsRoot -File -ErrorAction SilentlyContinue | Sort-Object Name
if ($shots) {
  foreach ($shot in $shots) {
    $summary += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
  }
}
else {
  $summary += "- No screenshots were captured."
}
$summary += ""
$summary += "## Notes"
$summary += ""
$summary += "- This pack combines client unit tests, server regression tests, cloud regression, customer onboarding regressions, known-issue regressions, commercial regressions, MSI upgrade metadata checks, policy/compatibility suites, linked-cloud licensing regressions, and available visual captures."
$summary += "- Real-service incident/licensing/linked-cloud suites only run when `DuressAlertService` is already installed and running."
$summary += "- The monitor screenshot is captured against the isolated policy-suite server-data root so it reflects policy-aware client state."

Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host ""
Write-Host "Regression pack written to:" $OutputRoot
Write-Host "Summary:" $summaryPath

try {
  powershell -NoProfile -ExecutionPolicy Bypass -File $closeWindowsScript | Out-Null
}
catch {}

if ($failed.Count -gt 0) {
  throw ("Full regression pack completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
