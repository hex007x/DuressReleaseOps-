param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\e2e-proof\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$fullRegressionScript = Join-Path $scriptRoot "exercise-full-regression-pack.ps1"
$provisioningScript = Join-Path $scriptRoot "exercise-client-policy-provisioning-suite.ps1"
$licensingProofScript = Join-Path $scriptRoot "exercise-licensing-proof-pack.ps1"
$linkedCloudScript = Join-Path $scriptRoot "exercise-linked-cloud-regression-suite.ps1"
$cloudRegressionScript = Join-Path $scriptRoot "exercise-cloud-regression-suite.ps1"
$knownIssueRegressionScript = Join-Path $scriptRoot "exercise-known-issue-regression-suite.ps1"
$commercialRegressionScript = Join-Path $scriptRoot "exercise-commercial-regression-suite.ps1"
$msiUpgradeMetadataScript = Join-Path $scriptRoot "exercise-msi-upgrade-metadata-suite.ps1"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "E2E_PROOF_REPORT.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot | Out-Null

function Invoke-And-Capture {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  $logPath = Join-Path $logsRoot ($Name + ".log")
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

$fullRegressionRoot = Join-Path $OutputRoot "full-regression"
$provisioningRoot = Join-Path $OutputRoot "policy-provisioning"
$licensingRoot = Join-Path $OutputRoot "licensing-proof"
$linkedCloudRoot = Join-Path $OutputRoot "linked-cloud"
$cloudRoot = Join-Path $OutputRoot "cloud-regression"
$knownIssueRoot = Join-Path $OutputRoot "known-issue-regressions"
$commercialRoot = Join-Path $OutputRoot "commercial-regression"
$msiUpgradeRoot = Join-Path $OutputRoot "msi-upgrade-metadata"

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "01-full-regression-pack" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $fullRegressionScript -OutputRoot $fullRegressionRoot -IncludeRealService
}))

$results.Add((Invoke-And-Capture -Name "02-policy-provisioning-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $provisioningScript -OutputRoot $provisioningRoot
}))

$results.Add((Invoke-And-Capture -Name "03-licensing-proof-pack" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $licensingProofScript -OutputRoot $licensingRoot
}))

$results.Add((Invoke-And-Capture -Name "04-linked-cloud-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $linkedCloudScript -OutputRoot $linkedCloudRoot
}))

$results.Add((Invoke-And-Capture -Name "05-cloud-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $cloudRegressionScript -OutputRoot $cloudRoot
}))

$results.Add((Invoke-And-Capture -Name "06-known-issue-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $knownIssueRegressionScript -OutputRoot $knownIssueRoot
}))

$results.Add((Invoke-And-Capture -Name "07-commercial-regression-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $commercialRegressionScript -OutputRoot $commercialRoot
}))

$results.Add((Invoke-And-Capture -Name "08-msi-upgrade-metadata-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $msiUpgradeMetadataScript -OutputRoot $msiUpgradeRoot
}))

$lines = @()
$lines += "# End-To-End Proof Pack"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Included suites"
$lines += ""
$lines += "- Full regression pack with real-service coverage"
$lines += "- Client policy provisioning proof"
$lines += "- Licensing proof pack"
$lines += "- Linked-cloud regression suite"
$lines += "- Cloud regression suite"
$lines += "- Known-issue regression suite"
$lines += "- Commercial regression suite"
$lines += "- MSI upgrade metadata suite"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$lines += ""
$lines += "## Key artifacts"
$lines += ""
$lines += "- [Full regression summary]($($fullRegressionRoot -replace '\\','/')/REGRESSION_SUMMARY.md)"
$lines += "- [Provisioning proof summary]($($provisioningRoot -replace '\\','/')/PROVISIONING_SUMMARY.md)"
$lines += "- [Licensing proof report]($($licensingRoot -replace '\\','/')/LICENSING_PROOF_REPORT.md)"
$lines += "- [Linked cloud regression summary]($($linkedCloudRoot -replace '\\','/')/LINKED_CLOUD_REGRESSION_SUMMARY.md)"
$lines += "- [Cloud regression summary]($($cloudRoot -replace '\\','/')/CLOUD_REGRESSION_SUMMARY.md)"
$lines += "- [Known-issue regression summary]($($knownIssueRoot -replace '\\','/')/KNOWN_ISSUE_REGRESSION_SUMMARY.md)"
$lines += "- [Commercial regression summary]($($commercialRoot -replace '\\','/')/COMMERCIAL_REGRESSION_SUMMARY.md)"
$lines += "- [MSI upgrade metadata summary]($($msiUpgradeRoot -replace '\\','/')/MSI_UPGRADE_METADATA_SUMMARY.md)"
$lines += ""
$lines += "## Scope covered"
$lines += ""
$lines += "- Client unit and server regression tests"
$lines += "- Legacy and modern protocol compatibility"
$lines += "- Incident workflow and real-service licensing flows"
$lines += "- Server-managed signed client policy"
$lines += "- Pre-install client provisioning from the server side"
$lines += "- Trial, expired, production/full, and capacity enforcement scenarios"
$lines += "- Linked-cloud claim, replacement, renewal check-in, and key-rotation rehearsals"
$lines += "- Cloud unit/integration coverage, publish validation, live ready/login smoke, and authenticated MFA-backed installer access"
$lines += "- Trial extension, payment activation, subscription lifecycle, and Xero automation business-path regressions"
$lines += "- Client/server MSI versioning and upgrade-code packaging checks across current and previous cloud artifacts"
$lines += "- Specific regressions for fixed bugs such as claim-token recovery, admin route posts, TS install guidance, and monitor layout"

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "E2E proof pack written to: $OutputRoot"
Write-Host "Summary: $summaryPath"

if ($failed.Count -gt 0) {
  throw ("End-to-end proof pack completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
