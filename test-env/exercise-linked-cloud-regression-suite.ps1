param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\linked-cloud-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$SystemName = 'Main Reception Server',
  [string]$ClaimToken = 'DEV-CLAIM-DEFAULT',
  [string]$ReplacementClaimToken = 'DEV-REPLACEMENT-CLAIM',
  [string]$CloudClaimUrl = 'http://localhost:5186/api/systems/claim',
  [string]$CloudCheckinUrl = 'http://localhost:5186/api/licensing/checkin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$claimScript = Join-Path $scriptRoot "exercise-linked-cloud-claim.ps1"
$checkinScript = Join-Path $scriptRoot "exercise-linked-cloud-checkin.ps1"
$replacementScript = Join-Path $scriptRoot "exercise-linked-cloud-replacement.ps1"
$rotationScript = Join-Path $scriptRoot "exercise-linked-cloud-trusted-key-rotation.ps1"
$lifecycleScript = Join-Path $scriptRoot "exercise-linked-cloud-server-lifecycle.ps1"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "LINKED_CLOUD_REGRESSION_SUMMARY.md"

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

$results.Add((Invoke-And-Capture -Name "01-linked-cloud-claim" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $claimScript `
    -SystemName $SystemName `
    -ClaimToken $ClaimToken `
    -CloudClaimUrl $CloudClaimUrl `
    -ExpectTrialLicense
}))

$results.Add((Invoke-And-Capture -Name "02-linked-cloud-checkin" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $checkinScript `
    -CloudCheckinUrl $CloudCheckinUrl
}))

$results.Add((Invoke-And-Capture -Name "03-linked-cloud-replacement" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $replacementScript `
    -SystemName $SystemName `
    -ReplacementClaimToken $ReplacementClaimToken `
    -CloudClaimUrl $CloudClaimUrl
}))

$results.Add((Invoke-And-Capture -Name "04-linked-cloud-trusted-key-rotation" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $rotationScript
}))

$results.Add((Invoke-And-Capture -Name "05-linked-cloud-lifecycle" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $lifecycleScript `
    -SystemName $SystemName `
    -ClaimToken $ClaimToken `
    -CloudClaimUrl $CloudClaimUrl `
    -CloudCheckinUrl $CloudCheckinUrl `
    -IncludeTrialClaim `
    -IncludeRenewalRefresh
}))

$summary = @()
$summary += "# Linked Cloud Regression Suite"
$summary += ""
$summary += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summary += ""
$summary += "## Coverage"
$summary += ""
$summary += "- Trial/bootstrap claim against linked cloud"
$summary += "- Linked cloud renewal check-in with signed license refresh"
$summary += "- Replacement/disaster-recovery claim handover"
$summary += "- Trusted signing-key rotation and bundle deployment"
$summary += "- Combined lifecycle rehearsal across claim and renewal"
$summary += ""
$summary += "## Results"
$summary += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $summary += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$summary += ""
$summary += "## Notes"
$summary += ""
$summary += "- This suite is intended to be release-gating evidence for the most used linked-cloud licensing paths."
$summary += "- It complements, rather than replaces, the real-service licensing suite and server unit tests."

Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Linked cloud regression suite written to:" $OutputRoot
Write-Host "Summary:" $summaryPath

if ($failed.Count -gt 0) {
  throw ("Linked cloud regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
