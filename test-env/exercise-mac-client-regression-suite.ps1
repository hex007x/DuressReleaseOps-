param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\mac-client-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$MacHost = "duress-mac",
  [switch]$CollectRemoteSnapshot,
  [switch]$SkipFixtureGeneration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$macRepoRoot = Join-Path $workspaceRoot "_external\duress-mac"
$fixtureToolProject = Join-Path $macRepoRoot "DuressAlertMac\DuressAlert.PolicyFixtureTool\DuressAlert.PolicyFixtureTool.csproj"
$macValidationScript = Join-Path $macRepoRoot "scripts\run-mac-validation-batch.sh"
$macStateInspectScript = Join-Path $macRepoRoot "scripts\inspect-mac-client-state.sh"
$macWebhookFixtureScript = Join-Path $macRepoRoot "scripts\start-mac-webhook-fixture.sh"
$macLiveChecklist = Join-Path $macRepoRoot "docs\MAC_LIVE_VALIDATION_CHECKLIST_2026-04-29.md"
$macPolicyFixtureDoc = Join-Path $macRepoRoot "docs\MAC_POLICY_FIXTURE_PACK.md"
$logsRoot = Join-Path $OutputRoot "logs"
$fixtureRoot = Join-Path $OutputRoot "policy-fixtures"
$summaryPath = Join-Path $OutputRoot "MAC_CLIENT_REGRESSION_SUMMARY.md"

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

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "01-verify-mac-paths" -Action {
  foreach ($requiredPath in @(
    $macRepoRoot,
    $fixtureToolProject,
    $macValidationScript,
    $macStateInspectScript,
    $macWebhookFixtureScript,
    $macLiveChecklist,
    $macPolicyFixtureDoc
  )) {
    if (-not (Test-Path $requiredPath)) {
      throw "Required Mac path was not found: $requiredPath"
    }
    Write-Host "Found $requiredPath"
  }
}))

$results.Add((Invoke-And-Capture -Name "02-build-mac-policy-fixture-tool" -Action {
  dotnet build $fixtureToolProject
  if ($LASTEXITCODE -ne 0) {
    throw "Mac policy fixture tool build failed."
  }
}))

if (-not $SkipFixtureGeneration) {
  $results.Add((Invoke-And-Capture -Name "03-generate-mac-policy-fixtures" -Action {
    dotnet run --project $fixtureToolProject -- `
      --output-dir $fixtureRoot `
      --server-id ITDSCRIPTSVR01 `
      --policy-version ("releaseops-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    if ($LASTEXITCODE -ne 0) {
      throw "Mac policy fixture generation failed."
    }
  }))
}

if ($CollectRemoteSnapshot) {
  $results.Add((Invoke-And-Capture -Name "04-collect-remote-snapshot" -Action {
    $remoteCommand = @'
hostname
sw_vers
APP_ROOT="$HOME/Library/Application Support/Duress Alert"
echo "APP_ROOT=$APP_ROOT"
if [ -d "$APP_ROOT" ]; then
  ls -la "$APP_ROOT"
else
  echo "App root not created yet."
fi
'@
    ssh -o BatchMode=yes $MacHost $remoteCommand
    if ($LASTEXITCODE -ne 0) {
      throw "Remote Mac snapshot failed."
    }
  }))
}

$lines = @()
$lines += "# Mac Client Regression Suite"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$lines += ""
$lines += "## Ready for the next live Mac session"
$lines += ""
$lines += "- Shared entry point exists in `DuressReleaseOps`."
$lines += "- Mac policy fixtures can be generated from Windows before touching the Mac."
$lines += "- The Mac repo now includes a local state inspector, local webhook sink, and a date-specific live-session checklist."
$lines += "- Live connect proof is still blocked until the real Mac desktop can accept the Local Network prompt if it appears."
$lines += ""
$lines += "## Next commands on the Mac"
$lines += ""
$lines += "```sh"
$lines += "bash scripts/run-mac-validation-batch.sh"
$lines += "bash scripts/inspect-mac-client-state.sh"
$lines += "bash scripts/start-mac-webhook-fixture.sh"
$lines += "```"
$lines += ""
$lines += "## References"
$lines += ""
$lines += "- [Mac live checklist]($($macLiveChecklist -replace '\\','/'))"
$lines += "- [Mac policy fixture pack]($($macPolicyFixtureDoc -replace '\\','/'))"
$lines += "- [Generated local policy fixtures]($($fixtureRoot -replace '\\','/'))"

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) {
  throw ("Mac client regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}

Write-Host "Mac client regression suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
