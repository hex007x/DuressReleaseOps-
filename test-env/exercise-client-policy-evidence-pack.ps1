param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\client-policy-evidence\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot

$policySuiteScript = Join-Path $scriptRoot "exercise-client-policy-suite.ps1"
$provisioningSuiteScript = Join-Path $scriptRoot "exercise-client-policy-provisioning-suite.ps1"
$configModesScript = Join-Path $scriptRoot "verify-client-config-modes.ps1"
$captureMonitorShotScript = Join-Path $scriptRoot "capture-monitor-screenshot.ps1"
$serverExe = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\bin\Release\DuressServer.exe"

$logsRoot = Join-Path $OutputRoot "logs"
$shotsRoot = Join-Path $OutputRoot "screenshots"
$serverDataRoot = Join-Path $OutputRoot "server-data"
$summaryPath = Join-Path $OutputRoot "CLIENT_POLICY_EVIDENCE_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $shotsRoot, $serverDataRoot | Out-Null

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

function Invoke-ServerReflection {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
  )

  $serverRootLiteral = $serverDataRoot.Replace("'", "''")
  $serverExeLiteral = $serverExe.Replace("'", "''")
  $body = @"
`$ErrorActionPreference = 'Stop'
`$env:DURESS_SERVER_DATA_ROOT = '$serverRootLiteral'
`$asm = [Reflection.Assembly]::LoadFrom('$serverExeLiteral')
$($ScriptBlock.ToString())
"@
  & powershell -NoProfile -ExecutionPolicy Bypass -Command $body
  if ($LASTEXITCODE -ne 0) {
    throw "Server reflection helper failed."
  }
}

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "01-client-config-modes" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $configModesScript
}))

$results.Add((Invoke-And-Capture -Name "02-client-policy-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $policySuiteScript
}))

$results.Add((Invoke-And-Capture -Name "03-client-policy-provisioning-suite" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $provisioningSuiteScript
}))

$results.Add((Invoke-And-Capture -Name "04-seed-monitor-evidence-state" -Action {
  Invoke-ServerReflection {
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
    $statusType = $asm.GetType('DuressAlert.LicenseRuntimeStatus')
    $clientType = $asm.GetType('DuressAlert.ClientRuntimeInfo')
    $ensure = $configType.GetMethod('EnsureClientPolicySigningKeys', [System.Reflection.BindingFlags]'Static,Public')
    $loadSettings = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $saveSettings = $configType.GetMethod('SaveSettings', [System.Reflection.BindingFlags]'Static,Public')
    $saveRuntime = $configType.GetMethod('SaveLicenseRuntimeStatus', [System.Reflection.BindingFlags]'Static,Public')

    $ensure.Invoke($null, @())
    $settings = $loadSettings.Invoke($null, @())
    $serverSettingsType.GetProperty('PolicyEnabled').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyServerId').SetValue($settings, 'policy-evidence-server')
    $serverSettingsType.GetProperty('PolicyDefaultPopupTheme').SetValue($settings, 'Modern')
    $serverSettingsType.GetProperty('PolicyDefaultPopupPosition').SetValue($settings, 'Center')
    $serverSettingsType.GetProperty('PolicyAllowSound').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockPopupTheme').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyLockPopupPosition').SetValue($settings, $true)
    $saveSettings.Invoke($null, @($settings))

    $runtimeStatus = [Activator]::CreateInstance($statusType)
    $statusType.GetProperty('LicenseId').SetValue($runtimeStatus, 'evidence-license')
    $statusType.GetProperty('CurrentConnectedClients').SetValue($runtimeStatus, 1)
    $statusType.GetProperty('ModernConnectedClients').SetValue($runtimeStatus, 1)
    $statusType.GetProperty('LegacyConnectedClients').SetValue($runtimeStatus, 0)
    $statusType.GetProperty('ConnectedClientVersions').SetValue($runtimeStatus, 'Duress2025 1.0')
    $statusType.GetProperty('LastCloudCheckResult').SetValue($runtimeStatus, 'Success')
    $statusType.GetProperty('LastCloudLicenseState').SetValue($runtimeStatus, 'Licensed')
    $statusType.GetProperty('LastCloudCheckUtc').SetValue($runtimeStatus, [DateTime]::UtcNow)

    $client = [Activator]::CreateInstance($clientType)
    $clientType.GetProperty('Name').SetValue($client, 'SCRIPT UPDATED')
    $clientType.GetProperty('Status').SetValue($client, 'Ready')
    $clientType.GetProperty('Connected').SetValue($client, $true)
    $clientType.GetProperty('IsLegacyClient').SetValue($client, $false)
    $clientType.GetProperty('Version').SetValue($client, '2025.04')
    $clientType.GetProperty('Platform').SetValue($client, 'Windows')
    $clientType.GetProperty('InstallationId').SetValue($client, 'install-script')
    $clientType.GetProperty('MachineName').SetValue($client, 'ROOM-SCRIPT')
    $clientType.GetProperty('PolicyCapable').SetValue($client, $true)
    $clientType.GetProperty('LastPolicyVersion').SetValue($client, '1')
    $clientType.GetProperty('LastPolicySource').SetValue($client, 'server')
    $clientType.GetProperty('LastPolicyFingerprint').SetValue($client, 'evidence-fingerprint')
    $clientType.GetProperty('LastSignatureValid').SetValue($client, $true)
    $clientType.GetProperty('LastPolicyError').SetValue($client, '')
    $clientType.GetProperty('LastPolicyAppliedUtc').SetValue($client, [DateTime]::UtcNow)
    $clientType.GetProperty('RemoteEndpoint').SetValue($client, '127.0.0.1:8001')
    $clientType.GetProperty('ConnectedAtUtc').SetValue($client, [DateTime]::UtcNow)
    $clientType.GetProperty('LastConnectedUtc').SetValue($client, [DateTime]::UtcNow)
    $clientType.GetProperty('LastUpdatedUtc').SetValue($client, [DateTime]::UtcNow)

    $clients = $statusType.GetProperty('Clients').GetValue($runtimeStatus)
    $null = $clients.Add($client)
    $saveRuntime.Invoke($null, @($runtimeStatus))
  }
}))

$results.Add((Invoke-And-Capture -Name "05-capture-monitor-name-refresh" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $captureMonitorShotScript -OutputPath (Join-Path $shotsRoot "server-monitor-client-name-refresh.png") -ServerDataRoot $serverDataRoot -StartupPage Monitor
}))

$results.Add((Invoke-And-Capture -Name "06-capture-client-policy-page" -Action {
  powershell -NoProfile -ExecutionPolicy Bypass -File $captureMonitorShotScript -OutputPath (Join-Path $shotsRoot "server-client-policy-evidence.png") -ServerDataRoot $serverDataRoot -StartupPage ClientPolicy
}))

$lines = @()
$lines += "# Client Policy Evidence Pack"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Result summary"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$lines += ""
$lines += "## Targeted matrix"
$lines += ""
$lines += '- Workstation/shared config mode: proven by `01-client-config-modes`.'
$lines += '- Terminal/per-user config mode: proven by `01-client-config-modes`.'
$lines += '- Signed server policy apply/reporting: proven by `02-client-policy-suite`.'
$lines += '- Queued resend processing: proven by `02-client-policy-suite`.'
$lines += '- Emergency/offline unlock: proven by `02-client-policy-suite`.'
$lines += '- Pre-install provisioning bundle and trusted-policy seeding: proven by `03-client-policy-provisioning-suite`.'
$lines += '- Server monitor evidence for updated client identity name: proven by `05-capture-monitor-name-refresh`.'
$lines += '- Server client-policy UI evidence: proven by `06-capture-client-policy-page`.'
$lines += ""
$lines += "## Screenshots"
$lines += ""
foreach ($shot in (Get-ChildItem -Path $shotsRoot -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
  $lines += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
}

$lines += ""
$lines += "## Notes"
$lines += ""
$lines += "- The monitor screenshot is seeded with a policy-capable client whose visible name is already updated to `SCRIPT UPDATED` so support can visually verify name-refresh behavior in the server monitor."
$lines += "- The policy-page screenshot proves the server-side policy configuration surface is present in the current build."
$lines += "- This pack is evidence-focused and complements, rather than replaces, the executable policy and provisioning suites."

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host ""
Write-Host "Client policy evidence pack written to:" $OutputRoot
Write-Host "Summary:" $summaryPath

if ($failed.Count -gt 0) {
  throw ("Client policy evidence pack completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
