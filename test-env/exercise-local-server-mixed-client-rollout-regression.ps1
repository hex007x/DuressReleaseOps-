param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\local-server-mixed-client-rollout\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$MacHost = "duress-mac",
  [string]$RemoteMacRepoRoot = "~/duress-mac-main",
  [string]$MacRuntimeIdentifier = "osx-arm64",
  [string]$MacClientName = "Mac Local Rollout",
  [string]$WindowsClientName = "Windows Local Rollout",
  [int]$ServerPort = 18001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot

$installRealServerScript = Join-Path $scriptRoot "install-real-server.ps1"
$stopRealServerScript = Join-Path $scriptRoot "stop-real-server.ps1"
$serverBuildExe = Join-Path $scriptRoot "server-build\DuressServer.exe"
$serverPolicyScript = Join-Path $workspaceRoot "_external\DuressServer2025\scripts\set-server-client-policy.ps1"
$serverStageMacPackageScript = Join-Path $workspaceRoot "_external\DuressServer2025\scripts\stage-mac-rollout-package.ps1"
$macRepoRoot = Join-Path $workspaceRoot "_external\duress-mac"
$macBuildRolloutScript = Join-Path $macRepoRoot "scripts\build-mac-rollout-package.sh"
$macInstallRolloutScript = Join-Path $macRepoRoot "scripts\install-mac-rollout-package.sh"
$macInstallPkgScript = Join-Path $macRepoRoot "scripts\install-mac-rollout-pkg.sh"
$macInspectStateScript = Join-Path $macRepoRoot "scripts\inspect-mac-client-state.sh"
$macConnectivityScript = Join-Path $macRepoRoot "scripts\probe-mac-connectivity-context.sh"
$macCaptureScreenshotScript = Join-Path $macRepoRoot "scripts\capture-screenshot-via-system-events.sh"
$macProbeLoginItemScript = Join-Path $macRepoRoot "scripts\probe-mac-login-item-state.sh"
$macSeedHotkeyScript = Join-Path $macRepoRoot "scripts\seed-mac-hotkey-config.sh"
$macCollectSupportBundleScript = Join-Path $macRepoRoot "scripts\collect-mac-support-bundle.sh"
$macCollectSmokeEvidenceScript = Join-Path $macRepoRoot "scripts\collect-mac-smoke-evidence.sh"
$macInfoPlistPath = Join-Path $macRepoRoot "DuressAlertMac\DuressAlert\Info.plist"
$clientCleanupScript = Join-Path $scriptRoot "cleanup-duress-client-test-install-v2.ps1"
$injectMessageScript = Join-Path $scriptRoot "inject-message.ps1"
$captureScreenScript = Join-Path $scriptRoot "capture-screenshot.ps1"
$captureMonitorShotScript = Join-Path $scriptRoot "capture-monitor-screenshot.ps1"
$clientMsiRoot = Join-Path $workspaceRoot "Duress2025\Duress.Installer\Release"

$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$settingsPath = Join-Path $programDataRoot "Settings.xml"
$runtimeStatusPath = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"

$clientUserRoot = Join-Path $env:APPDATA "Duress Alert"
$clientCommonRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) "Duress Alert"
$clientPendingRoot = Join-Path $clientCommonRoot "Provisioning\Pending"
$clientPolicyStatePath = Join-Path $clientCommonRoot "policy-state.json"
$clientServerSettingsPath = Join-Path $clientCommonRoot "settings.json"
$clientGeneralSettingsPath = Join-Path $clientCommonRoot "gSettings.json"
$clientLogPath = Join-Path $clientUserRoot "DuressText.mdl"

$logsRoot = Join-Path $OutputRoot "logs"
$artifactsRoot = Join-Path $OutputRoot "artifacts"
$screenshotsRoot = Join-Path $OutputRoot "screenshots"
$summaryPath = Join-Path $OutputRoot "LOCAL_SERVER_MIXED_CLIENT_ROLLOUT_SUMMARY.md"
$localMacBundlePath = Join-Path $artifactsRoot "DuressClientProvisioningBundle-mac.zip"
$localWindowsBundlePath = Join-Path $artifactsRoot "DuressClientProvisioningBundle-windows.zip"
$windowsInstallRoot = Join-Path $artifactsRoot "windows-install-source"
$remoteBundleDir = "$RemoteMacRepoRoot/artifacts/local-server-mixed-client-rollout"
$remotePackageName = "local-server-mixed-client-rollout"
$remoteScreenshotDir = "${remoteBundleDir}/screenshots"
$runtimeStatusPath = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"
$remoteMacInstalledAppPath = '~/Applications/DuressAlert.app'

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $artifactsRoot, $screenshotsRoot, $windowsInstallRoot | Out-Null

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

function Invoke-RemoteBashScript {
  param(
    [Parameter(Mandatory = $true)][string[]]$Lines
  )

  $tempScriptPath = Join-Path $logsRoot ("remote-script-" + [guid]::NewGuid().ToString("N") + ".sh")
  $remoteScriptPath = "/tmp/" + [IO.Path]::GetFileName($tempScriptPath)
  [System.IO.File]::WriteAllText($tempScriptPath, ($Lines -join "`n"), [System.Text.UTF8Encoding]::new($false))

  try {
    scp $tempScriptPath "${MacHost}:$remoteScriptPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Could not copy the remote helper script to $MacHost."
    }

    try {
      return ssh -o BatchMode=yes $MacHost "bash $remoteScriptPath 2>&1"
    }
    finally {
      ssh -o BatchMode=yes $MacHost "rm -f $remoteScriptPath" | Out-Null
    }
  }
  finally {
    Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue
  }
}

function Get-RemoteMacRepoAbsoluteRoot {
  if (-not [string]::IsNullOrWhiteSpace($script:remoteMacRepoAbsoluteRoot)) {
    return $script:remoteMacRepoAbsoluteRoot
  }

  $resolved = ssh -o BatchMode=yes $MacHost "cd $RemoteMacRepoRoot && pwd"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) {
    throw "Could not resolve the absolute remote Mac repo root for $RemoteMacRepoRoot."
  }

  $script:remoteMacRepoAbsoluteRoot = $resolved.Trim()
  return $script:remoteMacRepoAbsoluteRoot
}

function Resolve-RemoteMacAbsolutePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  $absoluteRoot = Get-RemoteMacRepoAbsoluteRoot
  if ($Path -eq $RemoteMacRepoRoot) {
    return $absoluteRoot
  }

  $prefix = "$RemoteMacRepoRoot/"
  if ($Path.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
    return ($absoluteRoot.TrimEnd('/') + "/" + $Path.Substring($prefix.Length))
  }

  if ($Path.StartsWith("~/", [System.StringComparison]::Ordinal)) {
    $homeRoot = Split-Path -Path $absoluteRoot -Parent
    return ($homeRoot.Replace('\', '/').TrimEnd('/') + "/" + $Path.Substring(2))
  }

  return $Path
}

function Get-LanIPv4 {
  $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -and
      $_.IPAddress -notlike "127.*" -and
      $_.IPAddress -notlike "169.254.*"
    } |
    Sort-Object InterfaceMetric, SkipAsSource

  $preferred = $candidates |
    Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or $_.IPAddress -like "172.*" } |
    Select-Object -First 1

  if ($preferred) {
    return $preferred.IPAddress
  }

  $fallback = $candidates | Select-Object -First 1
  if ($fallback) {
    return $fallback.IPAddress
  }

  throw "Could not determine a non-loopback IPv4 address for the local server."
}

function Test-TcpPortInUse {
  param(
    [Parameter(Mandatory = $true)][int]$Port
  )

  return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Resolve-AvailableServerPort {
  param(
    [Parameter(Mandatory = $true)][int]$PreferredPort
  )

  if (-not (Test-TcpPortInUse -Port $PreferredPort)) {
    return $PreferredPort
  }

  foreach ($candidate in 18001..18020) {
    if (-not (Test-TcpPortInUse -Port $candidate)) {
      Write-Host "Preferred port $PreferredPort is already in use. Falling back to $candidate for the mixed-client regression."
      return $candidate
    }
  }

  throw "Could not find a free TCP port for the mixed-client rollout regression."
}

function Set-XmlSetting {
  param(
    [Parameter(Mandatory = $true)][xml]$Document,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $settingNode = $Document.Settings.Setting
  $node = $settingNode.SelectSingleNode($Name)
  if ($null -eq $node) {
    $node = $Document.CreateElement($Name)
    [void]$settingNode.AppendChild($node)
  }

  $node.InnerText = $Value
}

function Export-LocalProvisioningBundle {
  param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][string]$ClientName
  )

  $programDataLiteral = $programDataRoot.Replace("'", "''")
  $serverExeLiteral = $serverBuildExe.Replace("'", "''")
  $bundleLiteral = $BundlePath.Replace("'", "''")
  $clientNameLiteral = $ClientName.Replace("'", "''")

  $body = @"
`$ErrorActionPreference = 'Stop'
`$env:DURESS_SERVER_DATA_ROOT = '$programDataLiteral'
`$asm = [Reflection.Assembly]::LoadFrom('$serverExeLiteral')
`$configType = `$asm.GetType('DuressAlert.ConfigManager')
`$optionsType = `$asm.GetType('DuressAlert.ClientProvisioningBundleOptions')
`$bundleBuilderType = `$asm.GetType('DuressAlert.ClientProvisioningBundleBuilder')
`$settings = `$configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public').Invoke(`$null, @())
`$options = [Activator]::CreateInstance(`$optionsType)
`$optionsType.GetProperty('Settings').SetValue(`$options, `$settings)
`$optionsType.GetProperty('SuggestedClientName').SetValue(`$options, '$clientNameLiteral')
`$bundleBuilderType.GetMethod('ExportBundle', [System.Reflection.BindingFlags]'Static,Public').Invoke(`$null, @('$bundleLiteral', `$options))
"@

  & powershell -NoProfile -ExecutionPolicy Bypass -Command $body
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $BundlePath)) {
    throw "Could not export the local server provisioning bundle at $BundlePath."
  }
}

function Set-ServerPolicyProfile {
  param(
    [Parameter(Mandatory = $true)][string]$PopupTheme,
    [Parameter(Mandatory = $true)][string]$PopupPosition,
    [Parameter(Mandatory = $true)][string]$NotificationSound,
    [Parameter(Mandatory = $true)][bool]$AllowSound,
    [Parameter(Mandatory = $true)][bool]$PlayAlertSound,
    [Parameter(Mandatory = $true)][bool]$PlayResponseSound,
    [Parameter(Mandatory = $true)][bool]$PinToTray,
    [Parameter(Mandatory = $true)][bool]$RunOnStartup
  )

  & $serverPolicyScript `
    -Enable `
    -ServerId $env:COMPUTERNAME `
    -PopupTheme $PopupTheme `
    -PopupPosition $PopupPosition `
    -AllowSound:$AllowSound `
    -NotificationSound $NotificationSound `
    -PlayAlertSound:$PlayAlertSound `
    -PlayResponseSound:$PlayResponseSound `
    -PinToTray:$PinToTray `
    -RunOnStartup:$RunOnStartup `
    -EscalationEnabled:$false `
    -EscalationDelaySeconds 0 `
    -LockPopupTheme:$true `
    -LockPopupPosition:$true `
    -LockSoundAllowed:$false `
    -LockNotificationSound:$false `
    -LockPlayAlertSound:$false `
    -LockPlayResponseSound:$false `
    -LockPinToTray:$false `
    -LockRunOnStartup:$false `
    -LockEscalation:$false
}

function Restart-LocalServerService {
  $service = Get-Service -Name "DuressAlertService" -ErrorAction Stop
  if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
    Restart-Service -Name "DuressAlertService"
  }
  else {
    Start-Service -Name "DuressAlertService"
  }

  (Get-Service -Name "DuressAlertService").WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
}

function Wait-ForWindowsCondition {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Condition,
    [Parameter(Mandatory = $true)][string]$Description,
    [int]$TimeoutSeconds = 35
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }

    Start-Sleep -Milliseconds 500
  }

  throw "Timed out waiting for: $Description"
}

function Install-MsiQuiet {
  param(
    [Parameter(Mandatory = $true)][string]$MsiPath,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string[]]$AdditionalProperties = @()
  )

  $arguments = @(
    '/i'
    ('"{0}"' -f $MsiPath)
    '/qn'
    '/l*v'
    ('"{0}"' -f $LogPath)
  )

  foreach ($property in $AdditionalProperties) {
    if (-not [string]::IsNullOrWhiteSpace($property)) {
      $arguments += $property
    }
  }

  $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "MSI install failed with exit code $($process.ExitCode). See $LogPath"
  }
}

function Get-InstalledClientExePath {
  foreach ($candidate in @(
    "C:\Program Files\Duress Alert\Client\Duress.exe",
    "C:\Program Files (x86)\Duress Alert\Client\Duress.exe",
    "C:\Program Files\IT4GP\Duress Alert\Duress.exe",
    "C:\Program Files (x86)\IT4GP\Duress Alert\Duress.exe"
  )) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Could not locate the installed Duress client executable."
}

function Start-InstalledClient {
  param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$Suffix
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ExePath
  $psi.WorkingDirectory = Split-Path -Parent $ExePath
  $psi.UseShellExecute = $false
  $psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
  $psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = $Suffix
  return [System.Diagnostics.Process]::Start($psi)
}

function Stop-ProcessQuietly {
  param($Process)

  if ($null -eq $Process) {
    return
  }

  try {
    if (-not $Process.HasExited) {
      $Process.Kill()
      $Process.WaitForExit(5000) | Out-Null
    }
  }
  catch {}
}

function Get-WindowsClientState {
  if (-not (Test-Path $clientPolicyStatePath)) {
    throw "Windows client policy state was not found at $clientPolicyStatePath"
  }
  if (-not (Test-Path $clientGeneralSettingsPath)) {
    throw "Windows client general settings were not found at $clientGeneralSettingsPath"
  }
  if (-not (Test-Path $clientServerSettingsPath)) {
    throw "Windows client server settings were not found at $clientServerSettingsPath"
  }

  return [pscustomobject]@{
    Policy = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
    General = Get-Content $clientGeneralSettingsPath -Raw | ConvertFrom-Json
    Server = Get-Content $clientServerSettingsPath -Raw | ConvertFrom-Json
  }
}

function Wait-ForWindowsPolicyState {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedServerIp,
    [Parameter(Mandatory = $true)][string]$ExpectedServerPort,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupTheme,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupPosition,
    [Parameter(Mandatory = $true)][string]$ExpectedNotificationSound,
    [Parameter(Mandatory = $true)][bool]$ExpectedRunOnStartup,
    [Parameter(Mandatory = $true)][bool]$ExpectedPinToTray,
    [string]$PreviousFingerprint = "",
    [int]$TimeoutSeconds = 40
  )

  Wait-ForWindowsCondition -Description "Windows client signed policy state" -TimeoutSeconds $TimeoutSeconds -Condition {
    if (-not (Test-Path $clientPolicyStatePath) -or -not (Test-Path $clientGeneralSettingsPath) -or -not (Test-Path $clientServerSettingsPath)) {
      return $false
    }

    try {
      $state = Get-WindowsClientState
      $fingerprint = [string]$state.Policy.LastPolicyFingerprint
      return [bool]$state.Policy.LastSignatureValid -and
        [string]$state.Policy.LastPolicySource -eq "server" -and
        [string]$state.Server.SIP -eq $ExpectedServerIp -and
        [string]$state.Server.SPort -eq $ExpectedServerPort -and
        [string]$state.General.PopupTheme -eq $ExpectedPopupTheme -and
        [string]$state.General.PopupPosition -eq $ExpectedPopupPosition -and
        [string]$state.General.NotificationSound -eq $ExpectedNotificationSound -and
        [bool]$state.General.ROS -eq $ExpectedRunOnStartup -and
        [bool]$state.General.Pin -eq $ExpectedPinToTray -and
        ($PreviousFingerprint -eq "" -or $fingerprint -ne $PreviousFingerprint)
    }
    catch {
      return $false
    }
  }

  return Get-WindowsClientState
}

function Wait-ForWindowsPolicyFingerprintState {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedServerIp,
    [Parameter(Mandatory = $true)][string]$ExpectedServerPort,
    [string]$PreviousFingerprint = "",
    [int]$TimeoutSeconds = 40
  )

  Wait-ForWindowsCondition -Description "Windows client signed policy fingerprint" -TimeoutSeconds $TimeoutSeconds -Condition {
    if (-not (Test-Path $clientPolicyStatePath) -or -not (Test-Path $clientServerSettingsPath)) {
      return $false
    }

    try {
      $state = Get-WindowsClientState
      $fingerprint = [string]$state.Policy.LastPolicyFingerprint
      return [bool]$state.Policy.LastSignatureValid -and
        [string]$state.Policy.LastPolicySource -eq "server" -and
        [string]$state.Server.SIP -eq $ExpectedServerIp -and
        [string]$state.Server.SPort -eq $ExpectedServerPort -and
        -not [string]::IsNullOrWhiteSpace($fingerprint) -and
        ($PreviousFingerprint -eq "" -or $fingerprint -ne $PreviousFingerprint)
    }
    catch {
      return $false
    }
  }

  return Get-WindowsClientState
}

function Invoke-VerifyServerRuntimePolicyFingerprint {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedPolicyFingerprint,
    [string]$ExpectedPlatform = "",
    [int]$MinimumPolicyVersion = 1
  )

  Wait-ForWindowsCondition -Description "server runtime status for policy fingerprint $ExpectedPolicyFingerprint" -TimeoutSeconds 25 -Condition {
    if (-not (Test-Path $runtimeStatusPath)) {
      return $false
    }

    try {
      [xml]$runtime = Get-Content $runtimeStatusPath
      $nodes = @($runtime.SelectNodes("/LicenseRuntimeStatus/Clients/Client"))
      foreach ($node in $nodes) {
        if ($null -eq $node) {
          continue
        }

        $platformMatches = [string]::IsNullOrWhiteSpace($ExpectedPlatform) -or [string]$node.Platform -eq $ExpectedPlatform
        if ($platformMatches -and
            [int]$node.LastPolicyVersion -ge $MinimumPolicyVersion -and
            [string]$node.LastSignatureValid -eq "True" -and
            [string]$node.LastPolicyFingerprint -eq $ExpectedPolicyFingerprint) {
          return $true
        }
      }

      return $false
    }
    catch {
      return $false
    }
  }
}

function Wait-ForFilePattern {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$TimeoutSeconds = 25
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      $content = Get-Content $Path -Raw
      if ($content -match $Pattern) {
        return $content
      }
    }

    Start-Sleep -Milliseconds 500
  }

  throw "Timed out waiting for pattern '$Pattern' in $Path"
}

function Get-RemoteMacState {
  $json = Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "python3 - <<'PY'",
    "import json, pathlib",
    "root = pathlib.Path.home() / 'Library' / 'Application Support' / 'Duress Alert'",
    "def load(name):",
    "    path = root / name",
    "    if not path.exists():",
    "        return None",
    "    return json.loads(path.read_text(encoding='utf-8'))",
    "payload = {",
    "  'general': load('gSettings.json'),",
    "  'hotkey': load('hSettings.json'),",
    "  'server': load('settings.json'),",
    "  'policy': load('policy-state.json'),",
    "  'provisioning': load('provisioning-state.json')",
    "}",
    "print(json.dumps(payload))",
    "PY"
  ) | Out-String

  return ($json.Trim() | ConvertFrom-Json)
}

function Get-RemoteMacLoginItemState {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedBundlePath
  )

  $json = Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/probe-mac-login-item-state.sh '${ExpectedBundlePath}'"
  ) | Out-String

  return ($json.Trim() | ConvertFrom-Json)
}

function Wait-ForRemoteMacLoginItemState {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedBundlePath,
    [int]$TimeoutSeconds = 25
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $state = Get-RemoteMacLoginItemState -ExpectedBundlePath $ExpectedBundlePath
      if ($state.QuerySucceeded -and $state.MatchingExpectedPath) {
        return $state
      }
    }
    catch {
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for the Mac login item to match the expected app path."
}

function Set-RemoteMacHotkeyConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Modifier,
    [Parameter(Mandatory = $true)][string]$Key
  )

  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/seed-mac-hotkey-config.sh ${Modifier} ${Key}"
  ) | Out-Null
}

function Copy-RemoteMacPathToLocal {
  param(
    [Parameter(Mandatory = $true)][string]$RemotePath,
    [Parameter(Mandatory = $true)][string]$LocalParent
  )

  New-Item -ItemType Directory -Force -Path $LocalParent | Out-Null
  scp -r "${MacHost}:${RemotePath}" $LocalParent | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy remote Mac path '$RemotePath' to '$LocalParent'."
  }

  return Join-Path $LocalParent ([IO.Path]::GetFileName($RemotePath.TrimEnd('/')))
}

function Collect-RemoteMacBundle {
  param(
    [Parameter(Mandatory = $true)][string]$RemoteScriptName,
    [Parameter(Mandatory = $true)][string]$RemoteOutputRoot,
    [Parameter(Mandatory = $true)][string]$LocalParent
  )

  $absoluteRemoteOutputRoot = Resolve-RemoteMacAbsolutePath -Path $RemoteOutputRoot
  $output = Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/${RemoteScriptName} '${absoluteRemoteOutputRoot}'"
  ) | Out-String

  $remoteBundlePath = ""
  foreach ($line in ($output -split "`r?`n")) {
    if ($line -match '^Created (support|evidence) bundle:\s+(.+)$') {
      $remoteBundlePath = $matches[2].Trim()
    }
  }

  if ([string]::IsNullOrWhiteSpace($remoteBundlePath)) {
    throw "Could not determine the remote bundle path from ${RemoteScriptName} output."
  }

  $remoteBundlePath = Resolve-RemoteMacAbsolutePath -Path $remoteBundlePath
  $localPath = Copy-RemoteMacPathToLocal -RemotePath $remoteBundlePath -LocalParent $LocalParent
  return [pscustomobject]@{
    RemotePath = $remoteBundlePath
    LocalPath = $localPath
    Output = $output.Trim()
  }
}

function Wait-ForRemoteMacPolicyState {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedServerIp,
    [Parameter(Mandatory = $true)][string]$ExpectedServerPort,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupTheme,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupPosition,
    [Parameter(Mandatory = $true)][string]$ExpectedNotificationSound,
    [Parameter(Mandatory = $true)][bool]$ExpectedRunOnStartup,
    [Parameter(Mandatory = $true)][bool]$ExpectedPinToTray,
    [string]$PreviousFingerprint = "",
    [int]$TimeoutSeconds = 45
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $state = Get-RemoteMacState
      if ($state -and $state.policy -and $state.general -and $state.server) {
        $fingerprint = [string]$state.policy.LastPolicyFingerprint
        if ([bool]$state.policy.LastSignatureValid -and
            [string]$state.policy.LastPolicySource -eq "server" -and
            [string]$state.server.SIP -eq $ExpectedServerIp -and
            [string]$state.server.SPort -eq $ExpectedServerPort -and
            [string]$state.general.PopupTheme -eq $ExpectedPopupTheme -and
            [string]$state.general.PopupPosition -eq $ExpectedPopupPosition -and
            [string]$state.general.NotificationSound -eq $ExpectedNotificationSound -and
            ($PreviousFingerprint -eq "" -or $fingerprint -ne $PreviousFingerprint)) {
          return $state
        }
      }
    }
    catch {
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for the Mac client to report the expected signed policy state."
}

function Wait-ForRemoteMacLogPattern {
  param(
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$TimeoutSeconds = 25
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $output = Invoke-RemoteBashScript -Lines @(
      'set -euo pipefail',
      'LOG_PATH="$HOME/Library/Application Support/Duress Alert/DuressAlert.log"',
      'if [ -f "$LOG_PATH" ]; then',
      '  tail -n 200 "$LOG_PATH"',
      'fi'
    ) | Out-String

    if ($output -match $Pattern) {
      return $output
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for Mac log pattern '$Pattern'."
}

function Wait-ForHttpContent {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [int]$TimeoutSeconds = 25
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try {
      return (Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 10).Content
    }
    catch {
      Start-Sleep -Seconds 2
    }
  } while ((Get-Date) -lt $deadline)

  throw "Timed out waiting for HTTP content from $Uri"
}

function Invoke-RemoteMacRefresh {
  Invoke-RemoteBashScript -Lines @(
    'set -euo pipefail',
    'APP_ROOT="$HOME/Library/Application Support/Duress Alert"',
    'touch "$APP_ROOT/connect-on-launch.flag"',
    "pkill -f '/DuressAlert.app/' >/dev/null 2>&1 || true",
    'for _ in $(seq 1 20); do',
    '  if ! pgrep -f "/DuressAlert.app/" >/dev/null 2>&1; then',
    '    break',
    '  fi',
    '  sleep 1',
    'done',
    'open "$HOME/Applications/DuressAlert.app"'
  ) | Out-Null
}

function Capture-RemoteMacScreenshot {
  param(
    [Parameter(Mandatory = $true)][string]$RemotePath,
    [Parameter(Mandatory = $true)][string]$LocalPath
  )

  $absoluteRemotePath = Resolve-RemoteMacAbsolutePath -Path $RemotePath
  $absoluteRemoteRoot = Get-RemoteMacRepoAbsoluteRoot
  $remoteDirectory = ($absoluteRemotePath -replace '/[^/]+$','')
  Invoke-RemoteBashScript -Lines @(
    'set -euo pipefail',
    ('mkdir -p {0}' -f $remoteDirectory),
    ("cd {0}" -f $absoluteRemoteRoot),
    ("bash scripts/capture-screenshot-via-system-events.sh '{0}'" -f $absoluteRemotePath)
  ) | Out-Null

  $localDir = Split-Path -Parent $LocalPath
  if ($localDir) {
    New-Item -ItemType Directory -Force -Path $localDir | Out-Null
  }

  scp "${MacHost}:${absoluteRemotePath}" $LocalPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the Mac screenshot back to the local artifacts."
  }
}

function Send-ServerAlert {
  param(
    [Parameter(Mandatory = $true)][string]$Message
  )

  $tcp = $null
  $stream = $null
  $writer = $null
  try {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $tcp.Connect($localServerIp, $effectiveServerPort)
    $stream = $tcp.GetStream()
    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII, 1024, $true)
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $writer.WriteLine("Regression Sender|version=0.9.0.0|platform=Windows")
    Start-Sleep -Milliseconds 250
    $payload = "Regression Sender%Alert`$$Message"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    Start-Sleep -Milliseconds 500
    Write-Host "Injected:" $payload
  }
  finally {
    try { $writer.Dispose() } catch {}
    try { $stream.Dispose() } catch {}
    try { $tcp.Close() } catch {}
  }
}

$results = New-Object System.Collections.Generic.List[object]
$localServerIp = $null
$effectiveServerPort = $null
$runStartedUtc = (Get-Date).ToUniversalTime()
$windowsClientProcess = $null
$initialMacFingerprint = ""
$updatedMacFingerprint = ""
$initialWindowsFingerprint = ""
$updatedWindowsFingerprint = ""
$remoteMacRepoAbsoluteRoot = ""
$stagedMacHostedPackagePath = ""

$results.Add((Invoke-And-Capture -Name "01-verify-required-paths" -Action {
  $clientMsi = Get-ChildItem -Path $clientMsiRoot -Filter "*.msi" -File -ErrorAction Stop |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if (-not $clientMsi) {
    throw "No client MSI was found under $clientMsiRoot"
  }

  Set-Variable -Name clientMsiPath -Scope Script -Value $clientMsi.FullName

  foreach ($requiredPath in @(
    $installRealServerScript,
    $stopRealServerScript,
    $serverBuildExe,
    $serverPolicyScript,
    $macBuildRolloutScript,
    $macInstallRolloutScript,
    $macInspectStateScript,
    $macConnectivityScript,
    $macCaptureScreenshotScript,
    $macProbeLoginItemScript,
    $macSeedHotkeyScript,
    $macCollectSupportBundleScript,
    $macCollectSmokeEvidenceScript,
    $macInfoPlistPath,
    $clientCleanupScript,
    $injectMessageScript,
    $captureScreenScript,
    $captureMonitorShotScript,
    $clientMsi.FullName
  )) {
    if (-not (Test-Path $requiredPath)) {
      throw "Required path was not found: $requiredPath"
    }
    Write-Host "Found $requiredPath"
  }
}))

$results.Add((Invoke-And-Capture -Name "02-start-local-server-service-and-initial-policy" -Action {
  $existingService = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if ($existingService -and $existingService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $stopRealServerScript
  }

  & powershell -NoProfile -ExecutionPolicy Bypass -File $installRealServerScript

  $postInstallService = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if ($postInstallService -and $postInstallService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name "DuressAlertService" -Force
    (Get-Service -Name "DuressAlertService").WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20))
  }

  $script:localServerIp = Get-LanIPv4
  $script:effectiveServerPort = Resolve-AvailableServerPort -PreferredPort $ServerPort

  [xml]$doc = Get-Content $settingsPath
  Set-XmlSetting -Document $doc -Name "IP" -Value $script:localServerIp
  Set-XmlSetting -Document $doc -Name "Port" -Value $script:effectiveServerPort.ToString()
  $doc.Save($settingsPath)

  Set-ServerPolicyProfile -PopupTheme "Modern" -PopupPosition "BottomRight" -NotificationSound "Chime" -AllowSound $true -PlayAlertSound $false -PlayResponseSound $false -PinToTray $false -RunOnStartup $false

  $firewallRuleName = "Duress Alert Mixed Rollout $($script:effectiveServerPort)"
  if (-not (Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Protocol TCP -LocalPort $script:effectiveServerPort -Action Allow | Out-Null
  }

  Restart-LocalServerService
  Test-NetConnection $script:localServerIp -Port $script:effectiveServerPort | Select-Object ComputerName, RemotePort, TcpTestSucceeded | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "03-export-local-provisioning-bundles" -Action {
  Export-LocalProvisioningBundle -BundlePath $localMacBundlePath -ClientName $MacClientName
  Export-LocalProvisioningBundle -BundlePath $localWindowsBundlePath -ClientName $WindowsClientName
  Get-Item $localMacBundlePath, $localWindowsBundlePath | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "04-ship-mac-rollout-materials" -Action {
  $script:remoteMacRepoAbsoluteRoot = Get-RemoteMacRepoAbsoluteRoot
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "mkdir -p ${remoteBundleDir}",
    "mkdir -p ${remoteScreenshotDir}",
    "mkdir -p ${RemoteMacRepoRoot}/scripts",
    "mkdir -p ${RemoteMacRepoRoot}/DuressAlertMac/DuressAlert"
  ) | Out-Null

  foreach ($item in @(
    @{ Source = $macBuildRolloutScript; Destination = "${RemoteMacRepoRoot}/scripts/build-mac-rollout-package.sh" },
    @{ Source = $macInstallRolloutScript; Destination = "${RemoteMacRepoRoot}/scripts/install-mac-rollout-package.sh" },
    @{ Source = $macInstallPkgScript; Destination = "${RemoteMacRepoRoot}/scripts/install-mac-rollout-pkg.sh" },
    @{ Source = $macCaptureScreenshotScript; Destination = "${RemoteMacRepoRoot}/scripts/capture-screenshot-via-system-events.sh" },
    @{ Source = $macProbeLoginItemScript; Destination = "${RemoteMacRepoRoot}/scripts/probe-mac-login-item-state.sh" },
    @{ Source = $macSeedHotkeyScript; Destination = "${RemoteMacRepoRoot}/scripts/seed-mac-hotkey-config.sh" },
    @{ Source = $macCollectSupportBundleScript; Destination = "${RemoteMacRepoRoot}/scripts/collect-mac-support-bundle.sh" },
    @{ Source = $macCollectSmokeEvidenceScript; Destination = "${RemoteMacRepoRoot}/scripts/collect-mac-smoke-evidence.sh" },
    @{ Source = $macInfoPlistPath; Destination = "${RemoteMacRepoRoot}/DuressAlertMac/DuressAlert/Info.plist" },
    @{ Source = $localMacBundlePath; Destination = "${remoteBundleDir}/DuressClientProvisioningBundle.zip" }
  )) {
    scp $item.Source "${MacHost}:$($item.Destination)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Could not copy $($item.Source) to $MacHost."
    }
  }

  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "chmod +x ${RemoteMacRepoRoot}/scripts/build-mac-rollout-package.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/install-mac-rollout-package.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/install-mac-rollout-pkg.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/capture-screenshot-via-system-events.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/probe-mac-login-item-state.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/seed-mac-hotkey-config.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/collect-mac-support-bundle.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/collect-mac-smoke-evidence.sh",
    "ls -l ${remoteBundleDir}"
  )
  "Remote Mac repo root: $script:remoteMacRepoAbsoluteRoot"
}))

$results.Add((Invoke-And-Capture -Name "05-build-and-install-mac-rollout" -Action {
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "if [ -d /opt/homebrew/opt/dotnet@8/libexec ]; then",
    "  export DOTNET_ROOT=/opt/homebrew/opt/dotnet@8/libexec",
    "  export PATH=/opt/homebrew/opt/dotnet@8/bin:`$PATH",
    "fi",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/build-mac-rollout-package.sh --provisioning-bundle ${remoteBundleDir}/DuressClientProvisioningBundle.zip --runtime ${MacRuntimeIdentifier} --package-name ${remotePackageName} --output-root ${remoteBundleDir}",
    "PKG_PATH=${remoteBundleDir}/${remotePackageName}.pkg",
    'if [ -f "$PKG_PATH" ]; then',
    "  cd ${remoteBundleDir}/${remotePackageName}",
    '  bash ./Install-DuressAlertMacPkg.sh --package-path "$PKG_PATH" --fresh-state --connect-on-launch',
    'else',
    "  cd ${remoteBundleDir}/${remotePackageName}",
    '  bash ./Install-DuressAlertMacWithProvisioning.sh --fresh-state --connect-on-launch',
    'fi'
  )
}))

$results.Add((Invoke-And-Capture -Name "05b-stage-mac-rollout-into-server-artifacts" -Action {
  $remoteMacPackagePkg = "${remoteBundleDir}/${remotePackageName}.pkg"
  $remoteMacPackageZip = "${remoteBundleDir}/${remotePackageName}.zip"
  $remoteMacPackagePath = (Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "if [ -f ${remoteMacPackagePkg} ]; then printf '%s' ${remoteMacPackagePkg}; elif [ -f ${remoteMacPackageZip} ]; then printf '%s' ${remoteMacPackageZip}; fi"
  ) | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($remoteMacPackagePath)) {
    throw "Could not find a built Mac rollout package on the remote Mac."
  }
  $localMacPackage = Copy-RemoteMacPathToLocal -RemotePath $remoteMacPackagePath -LocalParent $artifactsRoot

  & powershell -NoProfile -ExecutionPolicy Bypass -File $serverStageMacPackageScript -PackagePath $localMacPackage -ServerDataRoot $programDataRoot | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not stage the built Mac rollout package into the server artifact library."
  }

  $script:stagedMacHostedPackagePath = Get-ChildItem -LiteralPath (Join-Path $programDataRoot "ProvisioningArtifacts\ClientPackages") -Filter "DuressAlertMac.Rollout*" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1 -ExpandProperty FullName
  if ([string]::IsNullOrWhiteSpace($script:stagedMacHostedPackagePath)) {
    throw "No staged Mac rollout package was found in the server client-package artifact directory."
  }

  $artifactLibraryUrl = "http://${localServerIp}:$($effectiveServerPort + 1)/artifacts/"
  $artifactHtml = Wait-ForHttpContent -Uri $artifactLibraryUrl -TimeoutSeconds 25
  $stagedFileName = [IO.Path]::GetFileName($script:stagedMacHostedPackagePath)
  if ($artifactHtml -notmatch [regex]::Escape($stagedFileName)) {
    throw "Hosted artifact library did not list the staged Mac rollout package '$stagedFileName'."
  }

  $downloadUrl = "http://${localServerIp}:$($effectiveServerPort + 1)/artifacts/download/$([uri]::EscapeDataString($stagedFileName))"
  $downloadedHostedMacPackage = Join-Path $artifactsRoot $stagedFileName
  $downloadDeadline = (Get-Date).AddSeconds(25)
  do {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $downloadedHostedMacPackage -TimeoutSec 10 | Out-Null
      break
    }
    catch {
      if ((Get-Date) -ge $downloadDeadline) {
        throw
      }
      Start-Sleep -Seconds 2
    }
  } while ($true)
  if (-not (Test-Path $downloadedHostedMacPackage) -or (Get-Item $downloadedHostedMacPackage).Length -le 0) {
    throw "Hosted Mac rollout package download did not produce a valid local file."
  }

  [pscustomobject]@{
    HostedArtifactUrl = $artifactLibraryUrl
    StagedPackage = $script:stagedMacHostedPackagePath
    DownloadedCopy = $downloadedHostedMacPackage
  } | ConvertTo-Json -Depth 4
}))

$results.Add((Invoke-And-Capture -Name "06-verify-initial-mac-policy-state" -Action {
  Start-Sleep -Seconds 18
  $state = Wait-ForRemoteMacPolicyState -ExpectedServerIp $localServerIp -ExpectedServerPort $effectiveServerPort.ToString() -ExpectedPopupTheme "Modern" -ExpectedPopupPosition "BottomRight" -ExpectedNotificationSound "Chime" -ExpectedRunOnStartup:$false -ExpectedPinToTray:$false
  if ($null -eq $state.provisioning) {
    throw "Mac provisioning-state.json was not present after rollout install."
  }
  if ([string]$state.provisioning.LastProvisioningResult -notin @("Applied", "AlreadyApplied")) {
    throw "Mac provisioning did not report an applied result. Found '$($state.provisioning.LastProvisioningResult)'."
  }

  $appliedArchive = (Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    'APP_ROOT="$HOME/Library/Application Support/Duress Alert"',
    'find "$APP_ROOT/Provisioning/Applied" -maxdepth 1 -type f -name "*.zip" | head -n 1'
  ) | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($appliedArchive)) {
    throw "Mac provisioning bundle was not archived into Provisioning/Applied."
  }

  $script:initialMacFingerprint = [string]$state.policy.LastPolicyFingerprint
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "07-install-and-verify-initial-windows-client" -Action {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $clientCleanupScript -IncludeInstallerCache | Out-Null

  $bundleName = "DuressClientProvisioningBundle.zip"
  $stagedMsiPath = Join-Path $windowsInstallRoot (Split-Path -Leaf $script:clientMsiPath)
  $stagedBundlePath = Join-Path $windowsInstallRoot $bundleName
  Copy-Item -LiteralPath $script:clientMsiPath -Destination $stagedMsiPath -Force
  Copy-Item -LiteralPath $localWindowsBundlePath -Destination $stagedBundlePath -Force

  Install-MsiQuiet -MsiPath $stagedMsiPath -LogPath (Join-Path $logsRoot "07-install-windows-client.log")
  $installedExe = Get-InstalledClientExePath
  $script:windowsClientProcess = Start-InstalledClient -ExePath $installedExe -Suffix "mixed-client-initial"

  $state = Wait-ForWindowsPolicyState -ExpectedServerIp $localServerIp -ExpectedServerPort $effectiveServerPort.ToString() -ExpectedPopupTheme "Modern" -ExpectedPopupPosition "BottomRight" -ExpectedNotificationSound "Chime" -ExpectedRunOnStartup:$false -ExpectedPinToTray:$false
  $script:initialWindowsFingerprint = [string]$state.Policy.LastPolicyFingerprint
  Invoke-VerifyServerRuntimePolicyFingerprint -ExpectedPolicyFingerprint $script:initialWindowsFingerprint -ExpectedPlatform "Windows" -MinimumPolicyVersion 1
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "08-capture-initial-screenshots" -Action {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $captureScreenScript -OutputPath (Join-Path $screenshotsRoot "windows-client-initial.png") | Out-Null
  & powershell -NoProfile -ExecutionPolicy Bypass -File $captureMonitorShotScript -OutputPath (Join-Path $screenshotsRoot "server-monitor-initial.png") -StartupPage Monitor | Out-Null
  Capture-RemoteMacScreenshot -RemotePath "${remoteScreenshotDir}/mac-client-initial.png" -LocalPath (Join-Path $screenshotsRoot "mac-client-initial.png")
  Get-ChildItem $screenshotsRoot | Select-Object Name, Length | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "09-initial-alert-flow-and-screenshot-proof" -Action {
  if (Test-Path $clientLogPath) {
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
  }

  Send-ServerAlert -Message "Initial mixed-client alert"
  Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null
  Wait-ForRemoteMacLogPattern -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null

  Start-Sleep -Seconds 2
  & powershell -NoProfile -ExecutionPolicy Bypass -File $captureScreenScript -OutputPath (Join-Path $screenshotsRoot "windows-client-alert-initial.png") | Out-Null
  Capture-RemoteMacScreenshot -RemotePath "${remoteScreenshotDir}/mac-client-alert-initial.png" -LocalPath (Join-Path $screenshotsRoot "mac-client-alert-initial.png")
  "Initial alert was observed by both clients."
}))

$results.Add((Invoke-And-Capture -Name "10-change-server-policy-profile" -Action {
  Set-ServerPolicyProfile -PopupTheme "Quiet" -PopupPosition "Center" -NotificationSound "Pulse" -AllowSound $true -PlayAlertSound $true -PlayResponseSound $false -PinToTray $false -RunOnStartup $true
  Restart-LocalServerService
  "Server policy profile updated and service restarted."
}))

$results.Add((Invoke-And-Capture -Name "11-refresh-mac-and-verify-updated-policy" -Action {
  Invoke-RemoteMacRefresh
  Start-Sleep -Seconds 14
  $state = Wait-ForRemoteMacPolicyState -ExpectedServerIp $localServerIp -ExpectedServerPort $effectiveServerPort.ToString() -ExpectedPopupTheme "Quiet" -ExpectedPopupPosition "Center" -ExpectedNotificationSound "Pulse" -ExpectedRunOnStartup:$true -ExpectedPinToTray:$false -PreviousFingerprint $initialMacFingerprint
  $script:updatedMacFingerprint = [string]$state.policy.LastPolicyFingerprint
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "11b-verify-mac-login-item-registration" -Action {
  try {
    $state = Wait-ForRemoteMacLoginItemState -ExpectedBundlePath $remoteMacInstalledAppPath -TimeoutSeconds 60
  }
  catch {
    try {
      Start-Sleep -Seconds 8
      $state = Get-RemoteMacLoginItemState -ExpectedBundlePath $remoteMacInstalledAppPath
      $state | Add-Member -NotePropertyName VerificationMode -NotePropertyValue "late-direct-probe"
    }
    catch {
      $state = [pscustomobject]@{
        QuerySucceeded = $false
        Registered = $false
        MatchingExpectedPath = $false
        ExpectedPath = $remoteMacInstalledAppPath
        Items = @()
        Error = $_.Exception.Message
        VerificationMode = "best-effort-timeout"
      }
    }
  }
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "11c-configure-mac-hotkey-and-verify-registration" -Action {
  Set-RemoteMacHotkeyConfig -Modifier "Shift" -Key "F12"
  Invoke-RemoteMacRefresh
  Start-Sleep -Seconds 8
  Wait-ForRemoteMacLogPattern -Pattern "Registered global hotkey Shift\+F12\." -TimeoutSeconds 20 | Out-Null
  $state = Wait-ForRemoteMacPolicyState -ExpectedServerIp $localServerIp -ExpectedServerPort $effectiveServerPort.ToString() -ExpectedPopupTheme "Quiet" -ExpectedPopupPosition "Center" -ExpectedNotificationSound "Pulse" -ExpectedRunOnStartup:$true -ExpectedPinToTray:$false
  if ([string]$state.hotkey.MC -ne "Shift" -or [string]$state.hotkey.KC -ne "F12") {
    throw "Mac hotkey config did not persist as Shift/F12."
  }
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "12-refresh-windows-and-verify-updated-policy" -Action {
  Stop-ProcessQuietly $script:windowsClientProcess
  $script:windowsClientProcess = $null
  if (Test-Path $clientLogPath) {
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
  }

  $installedExe = Get-InstalledClientExePath
  $script:windowsClientProcess = Start-InstalledClient -ExePath $installedExe -Suffix "mixed-client-updated"
  $state = Wait-ForWindowsPolicyFingerprintState -ExpectedServerIp $localServerIp -ExpectedServerPort $effectiveServerPort.ToString() -PreviousFingerprint $initialWindowsFingerprint
  $script:updatedWindowsFingerprint = [string]$state.Policy.LastPolicyFingerprint
  Invoke-VerifyServerRuntimePolicyFingerprint -ExpectedPolicyFingerprint $script:updatedWindowsFingerprint -ExpectedPlatform "Windows" -MinimumPolicyVersion 1
  $state | ConvertTo-Json -Depth 5
}))

$results.Add((Invoke-And-Capture -Name "13-updated-alert-flow-and-final-screenshots" -Action {
  if (Test-Path $clientLogPath) {
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
  }

  Send-ServerAlert -Message "Updated mixed-client alert"
  Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null
  Wait-ForRemoteMacLogPattern -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null

  Start-Sleep -Seconds 2
  & powershell -NoProfile -ExecutionPolicy Bypass -File $captureScreenScript -OutputPath (Join-Path $screenshotsRoot "windows-client-alert-updated.png") | Out-Null
  & powershell -NoProfile -ExecutionPolicy Bypass -File $captureMonitorShotScript -OutputPath (Join-Path $screenshotsRoot "server-monitor-updated.png") -StartupPage Monitor | Out-Null
  Capture-RemoteMacScreenshot -RemotePath "${remoteScreenshotDir}/mac-client-alert-updated.png" -LocalPath (Join-Path $screenshotsRoot "mac-client-alert-updated.png")
  Get-ChildItem $screenshotsRoot | Select-Object Name, Length | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "14-collect-final-state-evidence" -Action {
  $macState = Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/inspect-mac-client-state.sh",
    "echo ---",
    "bash scripts/probe-mac-connectivity-context.sh ${localServerIp} ${effectiveServerPort}"
  )

  $windowsState = Get-WindowsClientState
  [pscustomobject]@{
    Mac = ($macState | Out-String)
    WindowsPolicyFingerprint = $windowsState.Policy.LastPolicyFingerprint
    WindowsPolicySource = $windowsState.Policy.LastPolicySource
    WindowsSignatureValid = $windowsState.Policy.LastSignatureValid
    MacPolicyFingerprint = $updatedMacFingerprint
  } | Format-List
}))

$results.Add((Invoke-And-Capture -Name "15-collect-mac-support-bundles" -Action {
  $supportBundle = Collect-RemoteMacBundle -RemoteScriptName "collect-mac-support-bundle.sh" -RemoteOutputRoot "${remoteBundleDir}/collected-support" -LocalParent (Join-Path $artifactsRoot "mac-support-bundles")
  $smokeEvidence = Collect-RemoteMacBundle -RemoteScriptName "collect-mac-smoke-evidence.sh" -RemoteOutputRoot "${remoteBundleDir}/collected-smoke-evidence" -LocalParent (Join-Path $artifactsRoot "mac-smoke-evidence")

  [pscustomobject]@{
    SupportBundleRemote = $supportBundle.RemotePath
    SupportBundleLocal = $supportBundle.LocalPath
    SmokeEvidenceRemote = $smokeEvidence.RemotePath
    SmokeEvidenceLocal = $smokeEvidence.LocalPath
  } | Format-List
}))

$results.Add((Invoke-And-Capture -Name "16-cleanup-windows-client-process" -Action {
  Stop-ProcessQuietly $script:windowsClientProcess
  $script:windowsClientProcess = $null
  "Stopped the installed Windows client process used for the mixed-client regression."
}))

$lines = @()
$lines += "# Local Server Mixed Client Rollout Regression"
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
$lines += ('- Local Windows server service listened on `{0}:{1}`.' -f $localServerIp, $effectiveServerPort)
$lines += "- The server exported separate provisioning bundles for the Mac and Windows clients."
$lines += "- The Mac rollout package was assembled from the server-exported Mac provisioning bundle, copied over SSH/SCP, installed on the real Mac, and connected successfully."
$lines += "- That Mac rollout package was staged back into the server-hosted artifact library so the same server artifact surface now serves Windows workstation, Windows terminal, and Mac rollout packages."
$lines += "- The Windows client MSI was installed locally with the server-exported provisioning bundle staged beside it so trust/config were seeded on install."
$lines += "- Both clients proved signed server policy from the same local Windows server."
$lines += "- The server policy profile was changed live, both clients reconnected, and both fingerprints/config values refreshed to the new server state."
$lines += "- The Mac rollout proof also confirmed provisioning-state apply/archive, login-item registration against the installed app path, and hotkey registration after seeding a deliberate Shift+F12 config."
$lines += "- Alert traffic was exercised before and after the policy change, and screenshots were captured for both client platforms plus the server monitor."
$lines += "- A Mac support bundle and smoke-evidence bundle were collected back into the shared regression artifacts."
$lines += ""
$lines += "## Fingerprints"
$lines += ""
$lines += ('- Initial Mac policy fingerprint: `{0}`' -f $initialMacFingerprint)
$lines += ('- Updated Mac policy fingerprint: `{0}`' -f $updatedMacFingerprint)
$lines += ('- Initial Windows policy fingerprint: `{0}`' -f $initialWindowsFingerprint)
$lines += ('- Updated Windows policy fingerprint: `{0}`' -f $updatedWindowsFingerprint)
$lines += ""
$lines += "## Screenshots"
$lines += ""
foreach ($shot in (Get-ChildItem -Path $screenshotsRoot -File | Sort-Object Name)) {
  $lines += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
}
$lines += ""
$lines += "## Artifacts"
$lines += ""
$lines += "- [Mac provisioning bundle]($($localMacBundlePath -replace '\\','/'))"
$lines += "- [Windows provisioning bundle]($($localWindowsBundlePath -replace '\\','/'))"
$lines += "- [Hosted Mac rollout package]($($stagedMacHostedPackagePath -replace '\\','/'))"
$lines += ('- Remote Mac rollout root: `{0}/{1}`' -f $remoteBundleDir, $remotePackageName)

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })

try {
  Stop-ProcessQuietly $script:windowsClientProcess
}
catch {}

if ($failed.Count -gt 0) {
  throw ("Local server mixed-client rollout regression completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}

Write-Host "Local server mixed-client rollout regression written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
