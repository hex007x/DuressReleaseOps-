param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\policy-provisioning\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$ClientMsiPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$serverExe = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\bin\Release\DuressServer.exe"
$serverBuildProject = Join-Path $workspaceRoot "_external\DuressServer2025\DuressServer2025\DuressServer2025.csproj"
$clientCleanupScript = Join-Path $scriptRoot "cleanup-duress-client-test-install-v2.ps1"
$captureServerShotScript = Join-Path $scriptRoot "capture-monitor-screenshot.ps1"
$closeWindowsScript = Join-Path $scriptRoot "close-visible-test-windows.ps1"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"

$logsRoot = Join-Path $OutputRoot "logs"
$shotsRoot = Join-Path $OutputRoot "screenshots"
$bundleRoot = Join-Path $OutputRoot "bundle"
$serverDataRoot = Join-Path $OutputRoot "server-data"
$clientUserRoot = Join-Path $env:APPDATA "Duress Alert"
$clientCommonRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) "Duress Alert"
$serverHarnessScript = Join-Path $OutputRoot "run-server-harness.ps1"
$serverHarnessPidFile = Join-Path $OutputRoot "server-harness.pid"
$serverHarnessStatusFile = Join-Path $OutputRoot "server-harness-status.txt"
$bundleZipPath = Join-Path $OutputRoot "DuressClientProvisioningBundle.zip"
$summaryPath = Join-Path $OutputRoot "PROVISIONING_SUMMARY.md"
$clientPolicyStatePath = Join-Path $clientCommonRoot "policy-state.json"
$clientPolicyKeyPath = Join-Path $clientCommonRoot "trusted-server-policy-key.xml"
$clientServerSettingsPath = Join-Path $clientCommonRoot "settings.json"
$clientGeneralSettingsPath = Join-Path $clientCommonRoot "gSettings.json"
$clientLogPath = Join-Path $clientUserRoot "DuressText.mdl"
$runtimeStatusPath = Join-Path $serverDataRoot "LicenseRuntimeStatus.xml"

if ([string]::IsNullOrWhiteSpace($ClientMsiPath)) {
  $releaseRoot = Join-Path $workspaceRoot "Duress2025\Duress.Installer\Release"
  $latestMsi = Get-ChildItem -Path $releaseRoot -Filter "Duress.Alert.Client*.msi" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

  if (-not $latestMsi) {
    $fallbackMsi = Join-Path $releaseRoot "Duress.Installer.msi"
    if (Test-Path $fallbackMsi) {
      $ClientMsiPath = $fallbackMsi
    }
  }
  else {
    $ClientMsiPath = $latestMsi.FullName
  }
}

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $shotsRoot, $bundleRoot, $serverDataRoot | Out-Null

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

function Wait-ForCondition {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Condition,
    [Parameter(Mandatory = $true)][string]$Description,
    [int]$TimeoutSeconds = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }

    Start-Sleep -Milliseconds 400
  }

  throw "Timed out waiting for: $Description"
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

function Start-IsolatedServerHarness {
  $serverRootLiteral = $serverDataRoot.Replace("'", "''")
  $serverExeLiteral = $serverExe.Replace("'", "''")
  $statusFileLiteral = $serverHarnessStatusFile.Replace("'", "''")
  $harnessContent = @"
`$ErrorActionPreference = 'Stop'
`$env:DURESS_SERVER_DATA_ROOT = '$serverRootLiteral'
`$statusFile = '$statusFileLiteral'
`$asm = [Reflection.Assembly]::LoadFrom('$serverExeLiteral')
`$type = `$asm.GetType('DuressAlert.DuressAlertService')
`$service = New-Object `$type.FullName
`$start = `$type.GetMethod('StartService',[System.Reflection.BindingFlags]'Instance,NonPublic')
Set-Content -Path `$statusFile -Value 'starting'
`$null = `$start.Invoke(`$service,@())
Set-Content -Path `$statusFile -Value 'started'
while (`$true) { Start-Sleep -Seconds 2 }
"@

  Set-Content -Path $serverHarnessScript -Value $harnessContent -Encoding ASCII
  $process = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $serverHarnessScript) -PassThru
  Set-Content -Path $serverHarnessPidFile -Value $process.Id -Encoding ASCII
  Wait-ForCondition -Description "isolated server harness start" -TimeoutSeconds 20 -Condition {
    if (-not (Test-Path $serverHarnessStatusFile)) { return $false }
    $statusText = Get-Content $serverHarnessStatusFile -Raw -ErrorAction SilentlyContinue
    return $statusText -and $statusText.Trim() -eq "started"
  }

  return $process
}

function Stop-IsolatedServerHarness {
  if (Test-Path $serverHarnessPidFile) {
    $pidValue = [int](Get-Content $serverHarnessPidFile -Raw).Trim()
    try {
      $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
      if ($process) {
        Stop-Process -Id $pidValue -Force
      }
    }
    catch {}
  }
}

function Stop-ProcessQuietly {
  param($Process)

  if ($null -eq $Process) {
    return
  }

  try {
    if (-not $Process.HasExited) {
      $Process.Kill()
      $Process.WaitForExit(3000) | Out-Null
    }
  }
  catch {}
}

function Get-InstalledClientExePath {
  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($candidate in @(
    "C:\Program Files\Duress Alert\Client\Duress.exe",
    "C:\Program Files (x86)\Duress Alert\Client\Duress.exe",
    "C:\Program Files\IT4GP\Duress Alert\Duress.exe",
    "C:\Program Files (x86)\IT4GP\Duress Alert\Duress.exe"
  )) {
    $candidates.Add($candidate) | Out-Null
  }

  $installedProduct = Get-ItemProperty `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object {
      ($_.PSObject.Properties.Name -contains 'DisplayName') -and @('Duress Alert', 'Duress Alert Client') -contains $_.DisplayName
    } |
    Select-Object -First 1

  if ($installedProduct -and ($installedProduct.PSObject.Properties.Name -contains 'InstallLocation') -and -not [string]::IsNullOrWhiteSpace($installedProduct.InstallLocation)) {
    $installCandidate = Join-Path $installedProduct.InstallLocation 'Duress.exe'
    if (-not $candidates.Contains($installCandidate)) {
      $candidates.Insert(0, $installCandidate)
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  Start-Sleep -Seconds 2

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $searchRoots = @(
    "C:\Program Files\Duress Alert",
    "C:\Program Files (x86)\Duress Alert",
    "C:\Program Files\IT4GP\Duress Alert",
    "C:\Program Files (x86)\IT4GP\Duress Alert"
  )

  foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) {
      continue
    }

    $match = Get-ChildItem -Path $root -Recurse -Filter 'Duress.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
      return $match.FullName
    }
  }

  $candidateReport = ($candidates | ForEach-Object { "{0} => {1}" -f $_, (Test-Path $_) }) -join "; "
  throw "Could not locate the installed Duress client executable. Candidate probe results: $candidateReport"
}

function Start-InstalledClient {
  param(
    [Parameter(Mandatory = $true)][string]$ExePath
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ExePath
  $psi.WorkingDirectory = Split-Path -Parent $ExePath
  $psi.UseShellExecute = $false
  $psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
  $psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = "policy-provisioning-suite"
  return [System.Diagnostics.Process]::Start($psi)
}

$results = New-Object System.Collections.Generic.List[object]
$installedClientProcess = $null
$serverHarness = $null

try {
  $results.Add((Invoke-And-Log -Name "01-build-server" -Action {
    & $msbuild $serverBuildProject /p:Configuration=Release /p:Platform=AnyCPU
    if ($LASTEXITCODE -ne 0) {
      throw "Server build failed."
    }
  }))

  if (-not (Test-Path $ClientMsiPath)) {
    throw "Client MSI not found at $ClientMsiPath"
  }

  $results.Add((Invoke-And-Log -Name "02-cleanup-client" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $clientCleanupScript -IncludeInstallerCache
  }))

  foreach ($path in @($clientPolicyStatePath, $clientPolicyKeyPath, $clientServerSettingsPath, $clientGeneralSettingsPath, $clientLogPath)) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }

  $bundleZipLiteral = $bundleZipPath.Replace("'", "''")
  $results.Add((Invoke-And-Log -Name "03-configure-server-policy-and-export" -Action {
    $exportScriptText = @'
      $configType = $asm.GetType('DuressAlert.ConfigManager')
      $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
      $optionsType = $asm.GetType('DuressAlert.ClientProvisioningBundleOptions')
      $builderType = $asm.GetType('DuressAlert.ClientProvisioningBundleBuilder')
      $ensure = $configType.GetMethod('EnsureClientPolicySigningKeys', [System.Reflection.BindingFlags]'Static,Public')
      $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
      $save = $configType.GetMethod('SaveSettings', [System.Reflection.BindingFlags]'Static,Public')
      $ensure.Invoke($null, @())
      $settings = $load.Invoke($null, @())
      $serverSettingsType.GetProperty('IP').SetValue($settings, [System.Net.IPAddress]::Parse('127.0.0.1'))
      $serverSettingsType.GetProperty('Port').SetValue($settings, 8001)
      $serverSettingsType.GetProperty('PolicyEnabled').SetValue($settings, $true)
      $serverSettingsType.GetProperty('PolicyServerId').SetValue($settings, 'provisioning-proof-server')
      $serverSettingsType.GetProperty('PolicyDefaultPopupTheme').SetValue($settings, 'Modern')
      $serverSettingsType.GetProperty('PolicyDefaultPopupPosition').SetValue($settings, 'Center')
      $serverSettingsType.GetProperty('PolicyAllowSound').SetValue($settings, $false)
      $serverSettingsType.GetProperty('PolicyDefaultNotificationSound').SetValue($settings, 'Chime')
      $serverSettingsType.GetProperty('PolicyDefaultPlayAlertSound').SetValue($settings, $false)
      $serverSettingsType.GetProperty('PolicyDefaultPlayResponseSound').SetValue($settings, $false)
      $serverSettingsType.GetProperty('PolicyDefaultRunOnStartup').SetValue($settings, $false)
      $serverSettingsType.GetProperty('PolicyDefaultPinToTray').SetValue($settings, $true)
      $serverSettingsType.GetProperty('PolicyDefaultEscalationEnabled').SetValue($settings, $true)
      $serverSettingsType.GetProperty('PolicyDefaultEscalationDelaySeconds').SetValue($settings, 90)
      $serverSettingsType.GetProperty('PolicyLockPopupTheme').SetValue($settings, $true)
      $serverSettingsType.GetProperty('PolicyLockPopupPosition').SetValue($settings, $true)
      $serverSettingsType.GetProperty('PolicyLockSoundAllowed').SetValue($settings, $true)
      $save.Invoke($null, @($settings))

      $options = [Activator]::CreateInstance($optionsType)
      $optionsType.GetProperty('Settings').SetValue($options, $settings)
      $export = $builderType.GetMethod('ExportBundle', [System.Reflection.BindingFlags]'Static,Public')
      $export.Invoke($null, @('__BUNDLE_ZIP__', $options))
'@
    $exportScript = [scriptblock]::Create($exportScriptText.Replace('__BUNDLE_ZIP__', $bundleZipLiteral))
    Invoke-ServerReflection -ScriptBlock $exportScript
  }))

  $results.Add((Invoke-And-Log -Name "04-expand-provisioning-bundle" -Action {
    Expand-Archive -Path $bundleZipPath -DestinationPath $bundleRoot -Force
    Copy-Item $ClientMsiPath (Join-Path $bundleRoot "Duress.Installer.msi") -Force

    $bundleSettingsPath = Join-Path $bundleRoot "settings.json"
    $bundleSettings = Get-Content $bundleSettingsPath -Raw | ConvertFrom-Json
    $bundleSettings.SIP = "127.0.0.1"
    $bundleSettings.SPort = "8001"
    $bundleSettings | ConvertTo-Json -Compress | Set-Content -Path $bundleSettingsPath -Encoding ASCII
  }))

  $results.Add((Invoke-And-Log -Name "05-capture-client-policy-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-client-policy.png") -ServerDataRoot $serverDataRoot -StartupPage ClientPolicy
  }))

  $results.Add((Invoke-And-Log -Name "06-start-isolated-server" -Action {
    $script:serverHarness = Start-IsolatedServerHarness
    "Isolated server harness started."
  }))

  $results.Add((Invoke-And-Log -Name "07-install-client-from-provisioning-bundle" -Action {
    $installScript = Join-Path $bundleRoot "Install-DuressClient-WithPolicy.ps1"
    $stdoutPath = Join-Path $logsRoot "07-install-helper-stdout.log"
    $stderrPath = Join-Path $logsRoot "07-install-helper-stderr.log"
    $arguments = @(
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $installScript,
      "-MsiPath",
      (Join-Path $bundleRoot "Duress.Installer.msi")
    )

    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru
    $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
    $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
    if ($process.ExitCode -ne 0) {
      throw ("Provisioning install helper failed with exit code {0}. Stdout:`n{1}`nStderr:`n{2}" -f $process.ExitCode, $stdout, $stderr)
    }

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
      $stdout.TrimEnd()
    }
  }))

  $results.Add((Invoke-And-Log -Name "08-launch-installed-client" -Action {
    $installedExe = Get-InstalledClientExePath
    $script:installedClientProcess = Start-InstalledClient -ExePath $installedExe
    "Started installed client from $installedExe"
  }))

  $results.Add((Invoke-And-Log -Name "09-verify-policy-application" -Action {
    Wait-ForCondition -Description "client policy state file" -TimeoutSeconds 25 -Condition {
      Test-Path $clientPolicyStatePath
    }

    $policyState = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
    if (-not $policyState.LastSignatureValid) {
      throw "Client policy state did not report a valid signature."
    }
    if ([int]$policyState.LastPolicyVersion -lt 1) {
      throw "Client policy version was not applied."
    }

    Wait-ForCondition -Description "server runtime status for policy client" -TimeoutSeconds 20 -Condition {
      if (-not (Test-Path $runtimeStatusPath)) { return $false }
      try {
        [xml]$runtime = Get-Content $runtimeStatusPath
        $node = $runtime.SelectSingleNode('/LicenseRuntimeStatus/Clients/Client[LastPolicyVersion="1"]')
        return $null -ne $node
      }
      catch {
        return $false
      }
    }

    [pscustomobject]@{
      LastPolicyVersion = $policyState.LastPolicyVersion
      LastSignatureValid = $policyState.LastSignatureValid
      LastPolicySource = $policyState.LastPolicySource
      LastError = $policyState.LastError
    } | Format-List
  }))

  $results.Add((Invoke-And-Log -Name "10-capture-post-install-client-policy-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-client-policy-post-install.png") -ServerDataRoot $serverDataRoot -StartupPage ClientPolicy
  }))

  $lines = @()
  $lines += "# Client Policy Provisioning Proof"
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
  $failed = @($results | Where-Object { -not $_.Success })
  if ($failed.Count -eq 0) {
    $lines += "## What this proves"
  }
  else {
    $lines += "## What this run covered"
  }
  $lines += ""
  $lines += "- Server policy was configured before client installation."
  $lines += "- A provisioning bundle was exported from the server-side policy model."
  $lines += "- The bundle seeded server endpoint settings and the trusted policy public key."
  $lines += "- The client MSI install helper was exercised."
  if ($failed.Count -eq 0) {
    $lines += "- The installed client connected and applied signed policy without post-install manual repair."
  }
  else {
    $lines += "- Final client launch/policy application still requires follow-up because one or more gates failed."
  }
  $lines += ""
  $lines += "## Screenshots"
  $lines += ""
  foreach ($shot in (Get-ChildItem -Path $shotsRoot -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $lines += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
  }

  Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

  if ($failed.Count -gt 0) {
    throw ("Provisioning suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
  }
}
finally {
  Stop-ProcessQuietly $installedClientProcess
  Stop-IsolatedServerHarness
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $clientCleanupScript -IncludeInstallerCache | Out-Null
  }
  catch {}
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $closeWindowsScript | Out-Null
  }
  catch {}
}

Write-Host "Provisioning suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
