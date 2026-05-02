param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\server-deployment-ui-smoke\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$serverExe = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\bin\Release\DuressServer.exe"
$serverProject = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\DuressServer2025.csproj"
$captureServerShotScript = Join-Path $scriptRoot "capture-monitor-screenshot.ps1"
$closeWindowsScript = Join-Path $scriptRoot "close-visible-test-windows.ps1"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"

$logsRoot = Join-Path $OutputRoot "logs"
$shotsRoot = Join-Path $OutputRoot "screenshots"
$serverDataRoot = Join-Path $OutputRoot "server-data"
$summaryPath = Join-Path $OutputRoot "SERVER_DEPLOYMENT_UI_SMOKE_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $shotsRoot, $serverDataRoot | Out-Null

function Invoke-And-Log {
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

function Invoke-UiInspection {
  $serverRootLiteral = $serverDataRoot.Replace("'", "''")
  $serverExeLiteral = $serverExe.Replace("'", "''")
  $validationPath = (Join-Path $OutputRoot "ui-validation.json").Replace("'", "''")
  $inspectionScriptPath = Join-Path $OutputRoot "invoke-ui-inspection.ps1"

  $scriptText = @"
`$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$env:DURESS_SERVER_DATA_ROOT = '$serverRootLiteral'
`$asm = [Reflection.Assembly]::LoadFrom('$serverExeLiteral')
`$formType = `$asm.GetType('DuressAlert.SettingsForm')
`$flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
`$staticFlags = [System.Reflection.BindingFlags]'Static,NonPublic'
`$form = [Activator]::CreateInstance(`$formType)
try {
  function Get-FieldValue {
    param([string]`$Name)
    return `$formType.GetField(`$Name, `$flags).GetValue(`$form)
  }

  `$tabControl = Get-FieldValue -Name 'tabControl1'
  if (`$null -eq `$tabControl) {
    throw 'The main tab control was not created.'
  }

  `$actualTabs = @(`$tabControl.TabPages | ForEach-Object { `$_.Text })
  `$requiredTabs = @('Manage', 'Policy', 'Deployment', 'Licensing', 'Support')
  foreach (`$requiredTab in `$requiredTabs) {
    if (`$actualTabs -notcontains `$requiredTab) {
      throw "Expected tab '`$requiredTab' was not present. Found: `$([string]::Join(', ', `$actualTabs))"
    }
  }

  `$tabPolicy = Get-FieldValue -Name 'tabClientPolicy'
  `$tabDeployment = Get-FieldValue -Name 'tabDeployment'
  `$tabLicensing = Get-FieldValue -Name 'tabLicense'
  `$formType.GetMethod('UpdateDeploymentWorkflowView', `$flags).Invoke(`$form, @()) | Out-Null

  if (-not `$tabPolicy.AutoScroll -or `$tabPolicy.AutoScrollMinSize.Height -lt 900) {
    throw 'The Policy tab no longer looks tall/scrollable enough for the rollout controls.'
  }
  if (-not `$tabDeployment.AutoScroll -or `$tabDeployment.AutoScrollMinSize.Height -lt 1200) {
    throw 'The Deployment tab no longer looks tall/scrollable enough for the rollout workflow.'
  }

  `$policySave = Get-FieldValue -Name 'btnPolicySaveGlobal'
  if (`$policySave.Text -ne 'Save Policy' -or `$policySave.Width -lt 120) {
    throw 'Save Policy was not present with the expected label and size on the Policy tab.'
  }

  `$requiredDeploymentButtons = @{
    btnFetchCloudClientMsi = 'Fetch Client MSI'
    btnExportWorkstationMsi = 'Build Workstation MSI'
    btnExportTerminalMsi = 'Build Terminal MSI'
  }
  foreach (`$entry in `$requiredDeploymentButtons.GetEnumerator()) {
    `$button = Get-FieldValue -Name `$entry.Key
    if (`$button.Text -ne `$entry.Value -or `$button.Width -lt 120) {
      throw "Deployment button '`$(`$entry.Value)' was not present with the expected label and size."
    }
  }

  `$deploymentButtons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
  `$collectButtons = {
    param([System.Windows.Forms.Control]`$control)
    foreach (`$child in `$control.Controls) {
      if (`$child -is [System.Windows.Forms.Button]) {
        `$deploymentButtons.Add([System.Windows.Forms.Button]`$child)
      }
      if (`$child.HasChildren) {
        & `$collectButtons `$child
      }
    }
  }
  & `$collectButtons `$tabDeployment
  if (-not (`$deploymentButtons | Where-Object { `$_.Text -eq 'Stage Mac Package' })) {
    throw 'Stage Mac Package was not present on the Deployment tab.'
  }

  `$summaryBox = Get-FieldValue -Name 'txtDeploymentSummary'
  if ([string]::IsNullOrWhiteSpace(`$summaryBox.Text) -or `$summaryBox.Text -notmatch 'Claim|Build|policy') {
    throw 'The deployment summary did not contain the expected workflow guidance.'
  }

  `$claimButton = Get-FieldValue -Name 'btnClaimCloud'
  `$serverUpdateButton = Get-FieldValue -Name 'btnExportServerUpdateKit'
  if (`$claimButton.Text -ne 'Claim Now') {
    throw 'Claim Now was not present on Licensing.'
  }
  if (`$serverUpdateButton.Text -ne 'Build Update Kit') {
    throw 'Build Update Kit was not present on Licensing.'
  }

  `$wizardMethod = `$formType.GetMethod('BuildDeploymentWizardHeadings', `$staticFlags)
  if (`$null -eq `$wizardMethod) {
    throw 'Could not locate BuildDeploymentWizardHeadings.'
  }
  `$wizardHeadings = @(`$wizardMethod.Invoke(`$null, @(`$false, `$false, `$false, `$false, `$false, `$false, `$false, `$false, `$false)))
  if (`$wizardHeadings.Count -lt 5) {
    throw 'The deployment wizard headings list was shorter than expected.'
  }

  `$result = [pscustomobject]@{
    Tabs = `$actualTabs
    WizardHeadings = `$wizardHeadings
    PolicyScrollHeight = `$tabPolicy.AutoScrollMinSize.Height
    DeploymentScrollHeight = `$tabDeployment.AutoScrollMinSize.Height
    DeploymentSummary = `$summaryBox.Text
  }
  `$result | ConvertTo-Json -Depth 6 | Set-Content -Path '$validationPath' -Encoding UTF8
  Write-Output ('$validationPath')
}
finally {
  try { `$form.Close() } catch {}
  try { `$form.Dispose() } catch {}
}
"@

  Set-Content -Path $inspectionScriptPath -Value $scriptText -Encoding UTF8

  $stdoutPath = Join-Path $OutputRoot "ui-inspection.stdout.log"
  $stderrPath = Join-Path $OutputRoot "ui-inspection.stderr.log"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$inspectionScriptPath`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $process = [System.Diagnostics.Process]::Start($psi)
  try {
    if (-not $process.WaitForExit(60000)) {
      try { $process.Kill() } catch {}
      throw "Server UI inspection timed out after 60 seconds."
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    Set-Content -Path $stdoutPath -Value $stdout -Encoding UTF8
    Set-Content -Path $stderrPath -Value $stderr -Encoding UTF8

    if ($process.ExitCode -ne 0) {
      throw ("Server UI inspection failed.`r`n" + $stdout + $stderr)
    }

    return ($stdout.Trim())
  }
  finally {
    try {
      if (-not $process.HasExited) {
        $process.Kill()
      }
    }
    catch {}
    $process.Dispose()
  }
}

$results = New-Object System.Collections.Generic.List[object]
$validationPath = ""

try {
  $results.Add((Invoke-And-Log -Name "01-build-server-release" -Action {
    & $msbuild $serverProject /t:Build /p:Configuration=Release /p:Platform=AnyCPU
    if ($LASTEXITCODE -ne 0) {
      throw "Server release build failed."
    }
  }))

  $results.Add((Invoke-And-Log -Name "02-inspect-deployment-ui" -Action {
    $script:validationPath = Invoke-UiInspection
    "UI inspection report: $script:validationPath"
  }))

  $results.Add((Invoke-And-Log -Name "03-capture-policy-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-policy-ui.png") -ServerDataRoot $serverDataRoot -StartupPage Policy
  }))

  $results.Add((Invoke-And-Log -Name "04-capture-deployment-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-deployment-ui.png") -ServerDataRoot $serverDataRoot -StartupPage Deployment
  }))

  $results.Add((Invoke-And-Log -Name "05-capture-licensing-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-licensing-ui.png") -ServerDataRoot $serverDataRoot -StartupPage Licensing
  }))

  $lines = @()
  $lines += "# Server Deployment UI Smoke Suite"
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
  $lines += "## Covered behaviour"
  $lines += ""
  $lines += "- The server WinForms shell rendered the expected top-level tabs for Manage, Policy, Deployment, Licensing, and Support."
  $lines += "- Policy and Deployment retained tall scrollable layouts so critical rollout controls are less likely to disappear below the fold."
  $lines += "- Save Policy, Fetch Client MSI, Build Workstation MSI, Build Terminal MSI, Stage Mac Package, Claim Now, and Build Update Kit were all present on their expected surfaces."
  $lines += "- Deployment wizard headings were still available for the guided rollout path."
  $lines += ""
  $lines += "## Artifacts"
  $lines += ""
  if (-not [string]::IsNullOrWhiteSpace($validationPath)) {
    $lines += "- [UI validation report]($($validationPath -replace '\\','/'))"
  }
  foreach ($shot in (Get-ChildItem -Path $shotsRoot -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $lines += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
  }

  Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

  $failed = @($results | Where-Object { -not $_.Success })
  if ($failed.Count -gt 0) {
    throw ("Server deployment UI smoke suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
  }
}
finally {
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $closeWindowsScript | Out-Null
  }
  catch {}
}

Write-Host "Server deployment UI smoke suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
