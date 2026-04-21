param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\communications-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudTestsProject = Join-Path $workspaceRoot "DuressCloud\tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj"
$cloudIntegrationProject = Join-Path $workspaceRoot "DuressCloud\tests\DuressCloud.Web.IntegrationTests\DuressCloud.Web.IntegrationTests.csproj"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "COMMUNICATIONS_REGRESSION_SUMMARY.md"

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
$results.Add((Invoke-And-Capture -Name "01-communications-cloud-tests" -Action {
  $filter = @(
    "FullyQualifiedName~CommunicationAutomationWorkerTests",
    "FullyQualifiedName~CommunicationTemplateRendererTests",
    "FullyQualifiedName~ManagementCommunicationsIndexTests",
    "FullyQualifiedName~AdminCommunicationsIndexTests",
    "FullyQualifiedName~AdminCommunicationCreateTests",
    "FullyQualifiedName~AdminCommunicationDetailsTests",
    "FullyQualifiedName~PortalCommunicationsIndexTests",
    "FullyQualifiedName~MarkupRegressionTests"
  ) -join "|"

  & dotnet test $cloudTestsProject --configuration Release --nologo --filter $filter
  if ($LASTEXITCODE -ne 0) {
    throw "Communications cloud regression tests failed."
  }
}))

$results.Add((Invoke-And-Capture -Name "02-communications-integration-tests" -Action {
  $filter = @(
    "FullyQualifiedName~ManagementCommunicationsIndexChallengesAnonymousUsers",
    "FullyQualifiedName~AdminCommunicationsIndexChallengesAnonymousUsers",
    "FullyQualifiedName~AdminCommunicationCreateChallengesAnonymousUsers",
    "FullyQualifiedName~AdminCommunicationDetailsChallengesAnonymousUsers",
    "FullyQualifiedName~PortalCommunicationsIndexChallengesAnonymousUsers"
  ) -join "|"

  & dotnet test $cloudIntegrationProject --configuration Release --nologo --filter $filter
  if ($LASTEXITCODE -ne 0) {
    throw "Communications integration regression tests failed."
  }
}))

$lines = @()
$lines += "# Communications Regression Suite"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Coverage"
$lines += ""
$lines += "- action-linked template rendering with stored plain-text and HTML bodies"
$lines += "- management communications configuration with timing overrides and token visibility"
$lines += "- one-off customer compose with and without template prefill"
$lines += "- customer/staff communications history and exact sent-message detail visibility"
$lines += "- scheduled trial and renewal automation cadence behavior"
$lines += "- anonymous route protection for management, admin, and portal communications pages"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Communications regression suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"

if ($failed.Count -gt 0) {
  throw ("Communications regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
