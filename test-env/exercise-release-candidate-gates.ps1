param(
    [string]$Version,
    [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\release-candidate-gates\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
    [switch]$IncludeMacRollout = $true,
    [switch]$IncludeMixedClientRollout = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$fullRegressionScript = Join-Path $PSScriptRoot "exercise-full-regression-pack.ps1"
$tlsRehearsalScript = Join-Path $PSScriptRoot "exercise-cloud-hostname-tls-rehearsal.ps1"
$publishedInstallerCheckScript = Join-Path $PSScriptRoot "verify-published-cloud-installers.ps1"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$summaryPath = Join-Path $OutputRoot "RELEASE_CANDIDATE_GATE_SUMMARY.md"

$steps = New-Object System.Collections.Generic.List[string]

Write-Host "Running release-candidate regression pack..."
powershell -NoProfile -ExecutionPolicy Bypass -File $fullRegressionScript `
    -RequireRealService `
    -IncludeMacRollout:$IncludeMacRollout `
    -IncludeMixedClientRollout:$IncludeMixedClientRollout `
    -OutputRoot (Join-Path $OutputRoot "full-regression")
$steps.Add("Full regression pack completed with real-service requirement.")

Write-Host "Running Cloud hostname/TLS rehearsal..."
powershell -NoProfile -ExecutionPolicy Bypass -File $tlsRehearsalScript `
    -OutputRoot (Join-Path $OutputRoot "cloud-hostname-tls") `
    -RestoreDefaultCloud
$steps.Add("Cloud hostname/TLS rehearsal completed.")

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Verifying published cloud installers for version $Version..."
    powershell -NoProfile -ExecutionPolicy Bypass -File $publishedInstallerCheckScript -Version $Version
    $steps.Add("Published cloud installer sanity check completed for $Version.")
}
else {
    $steps.Add("Published cloud installer sanity check skipped because -Version was not supplied.")
}

$summary = @(
    "# Release Candidate Gate Summary",
    "",
    "- Timestamp: $(Get-Date -Format 'u')",
    "- Version: $([string]::IsNullOrWhiteSpace($Version) ? '(not supplied)' : $Version)",
    "",
    "## Completed Steps",
    ""
)

$summary += $steps | ForEach-Object { "- $_" }
$summary | Set-Content -Path $summaryPath

Write-Host "Release candidate gate summary written to $summaryPath"
