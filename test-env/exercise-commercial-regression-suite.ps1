param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\commercial-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudTestsProject = Join-Path $workspaceRoot "DuressCloud\tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "COMMERCIAL_REGRESSION_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot | Out-Null

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

$results = New-Object System.Collections.Generic.List[object]
$results.Add((Invoke-And-Capture -Name "01-commercial-cloud-tests" -Action {
  $filter = @(
    "FullyQualifiedName~PaymentActivationServiceTests",
    "FullyQualifiedName~SubscriptionLifecycleServiceTests",
    "FullyQualifiedName~SubscriptionLifecycleAutomationServiceTests",
    "FullyQualifiedName~SubscriptionOperationsServiceTests",
    "FullyQualifiedName~XeroSyncAutomationWorkerTests",
    "FullyQualifiedName~CustomerTrialExtensionRegressionTests"
  ) -join "|"

  & dotnet test $cloudTestsProject --configuration Release --nologo --filter $filter
  if ($LASTEXITCODE -ne 0) {
    throw "Commercial cloud regression tests failed."
  }
}))

$lines = @()
$lines += "# Commercial Regression Suite"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Coverage"
$lines += ""
$lines += "- Trial extension page-model regression"
$lines += "- Payment activation and fulfillment regression"
$lines += "- Subscription creation and renewal regression"
$lines += "- Subscription lifecycle automation regression"
$lines += "- Subscription operations regression"
$lines += "- Xero sync automation regression"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Commercial regression suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"

if ($failed.Count -gt 0) {
  throw ("Commercial regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
