param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\known-issue-regressions\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudMarkupTestsProject = Join-Path $workspaceRoot "DuressCloud\tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj"
$serverTestsProject = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025.Tests\DuressServer2025.Tests.csproj"
$serverTestsExe = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025.Tests\bin\Release\DuressServer2025.Tests.exe"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "KNOWN_ISSUE_REGRESSION_SUMMARY.md"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot | Out-Null

function Stop-LingeringServerRegressionProcesses {
  $staleProcesses = Get-Process DuressServer2025.Tests, DuressServer -ErrorAction SilentlyContinue
  if ($staleProcesses) {
    $staleProcesses | Stop-Process -Force
    Start-Sleep -Milliseconds 500
  }
}

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

$results.Add((Invoke-And-Capture -Name "01-cloud-markup-regressions" -Action {
  & dotnet test $cloudMarkupTestsProject --configuration Release --nologo --filter "FullyQualifiedName~MarkupRegressionTests"
  if ($LASTEXITCODE -ne 0) {
    throw "Cloud markup regression tests failed."
  }
}))

$results.Add((Invoke-And-Capture -Name "02-server-regression-build" -Action {
  Stop-LingeringServerRegressionProcesses
  & $msbuild $serverTestsProject /t:Build /p:Configuration=Release /p:Platform=AnyCPU /p:BuildProjectReferences=false
  if ($LASTEXITCODE -ne 0) {
    throw "Server regression test build failed."
  }
}))

$results.Add((Invoke-And-Capture -Name "03-server-claim-and-layout-regressions" -Action {
  Stop-LingeringServerRegressionProcesses
  try {
    $output = & $serverTestsExe
    if ($LASTEXITCODE -ne 0) {
      throw "Server unit tests failed."
    }
  }
  finally {
    Stop-LingeringServerRegressionProcesses
  }

  $outputText = ($output | Out-String)

  $requiredMarkers = @(
    "Monitor layout uses resizable split containers for client visibility",
    "Cloud claim removes stale legacy registration when a signed license is applied",
    "Cloud claim fails closed when cloud confirms the claim but no signed license becomes active locally",
    "Configured cloud refresh prefers claim when a claim token is pending",
    "Provisioning bundle README explains workstation and terminal-services installs"
  )

  foreach ($marker in $requiredMarkers) {
    if ($outputText -notmatch [Regex]::Escape($marker)) {
      throw "Expected server regression marker was not present in output: $marker"
    }
  }

  $outputText
}))

$summary = @()
$summary += "# Known-Issue Regression Suite"
$summary += ""
$summary += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summary += ""
$summary += "## Coverage"
$summary += ""
$summary += "- Management back-link regression"
$summary += "- Customer edit/system edit route-id and return-url regression"
$summary += "- Terminal-services installer guide visibility and instructions"
$summary += "- Server operations monitor resizable layout regression"
$summary += "- Claim token, legacy-license conflict, and pending-claim regression"
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
$summary += "- This suite turns specific fixed bugs into named release gates so they do not fade back into tribal memory."
$summary += "- It complements the broader cloud, linked-cloud, client, and end-to-end packs."

Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Known-issue regression suite written to:" $OutputRoot
Write-Host "Summary:" $summaryPath

if ($failed.Count -gt 0) {
  throw ("Known-issue regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
