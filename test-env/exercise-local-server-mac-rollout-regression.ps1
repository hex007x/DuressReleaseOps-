param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\local-server-mac-rollout\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$MacHost = "duress-mac",
  [string]$RemoteMacRepoRoot = "~/duress-mac-main",
  [string]$MacRuntimeIdentifier = "osx-arm64",
  [string]$MacClientName = "Mac Local Rollout",
  [int]$ServerPort = 18001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot

$installRealServerScript = Join-Path $scriptRoot "install-real-server.ps1"
$startRealServerScript = Join-Path $scriptRoot "start-real-server.ps1"
$stopRealServerScript = Join-Path $scriptRoot "stop-real-server.ps1"
$serverBuildExe = Join-Path $scriptRoot "server-build\DuressServer.exe"
$serverPolicyScript = Join-Path $workspaceRoot "_external\DuressServer2025\scripts\set-server-client-policy.ps1"
$macRepoRoot = Join-Path $workspaceRoot "_external\duress-mac"
$macBuildRolloutScript = Join-Path $macRepoRoot "scripts\build-mac-rollout-package.sh"
$macInstallRolloutScript = Join-Path $macRepoRoot "scripts\install-mac-rollout-package.sh"
$macInspectStateScript = Join-Path $macRepoRoot "scripts\inspect-mac-client-state.sh"
$macConnectivityScript = Join-Path $macRepoRoot "scripts\probe-mac-connectivity-context.sh"
$macInfoPlistPath = Join-Path $macRepoRoot "DuressAlertMac\DuressAlert\Info.plist"

$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$settingsPath = Join-Path $programDataRoot "Settings.xml"
$runtimeStatusPath = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"

$logsRoot = Join-Path $OutputRoot "logs"
$artifactsRoot = Join-Path $OutputRoot "artifacts"
$summaryPath = Join-Path $OutputRoot "LOCAL_SERVER_MAC_ROLLOUT_SUMMARY.md"
$localBundlePath = Join-Path $artifactsRoot "DuressClientProvisioningBundle-local-mac.zip"
$remoteBundleDir = "$RemoteMacRepoRoot/artifacts/local-server-rollout"
$remotePackageName = "local-server-mac-rollout"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $artifactsRoot | Out-Null

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
      $nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
      if ($nativePreferenceVar) {
        $previousNativeErrorPreference = $nativePreferenceVar.Value
        $PSNativeCommandUseErrorActionPreference = $false
      }
      try {
        return ssh -o BatchMode=yes $MacHost "bash $remoteScriptPath 2>&1"
      }
      finally {
        if ($nativePreferenceVar) {
          $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
        }
      }
    }
    finally {
      ssh -o BatchMode=yes $MacHost "rm -f $remoteScriptPath" | Out-Null
    }
  }
  finally {
    Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue
  }
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
      Write-Host "Preferred port $PreferredPort is already in use. Falling back to $candidate for the local Mac rollout regression."
      return $candidate
    }
  }

  throw "Could not find a free TCP port for the local Mac rollout regression."
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
    throw "Could not export the local server provisioning bundle."
  }
}

function Wait-ForServerRuntimeClient {
  param(
    [Parameter(Mandatory = $true)][string]$ClientName,
    [Parameter(Mandatory = $true)][datetime]$RunStartedUtc,
    [int]$TimeoutSeconds = 40
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $runtimeStatusPath) {
      try {
        [xml]$runtime = Get-Content $runtimeStatusPath
        $healthyNodes = @($runtime.SelectNodes("/LicenseRuntimeStatus/Clients/Client[LastPolicySource='server' and LastSignatureValid='True']"))
        if ($healthyNodes.Count -gt 0) {
          $latestHealthyNode = $healthyNodes |
            Sort-Object {
              $stamp = $_.SelectSingleNode("LastPolicyAppliedUtc")
              if ($stamp -and -not [string]::IsNullOrWhiteSpace($stamp.InnerText)) {
                try {
                  return [datetime]::Parse($stamp.InnerText).ToUniversalTime()
                }
                catch {
                }
              }

              $updated = $_.SelectSingleNode("LastUpdatedUtc")
              if ($updated -and -not [string]::IsNullOrWhiteSpace($updated.InnerText)) {
                try {
                  return [datetime]::Parse($updated.InnerText).ToUniversalTime()
                }
                catch {
                }
              }

              return [datetime]::MinValue
            } -Descending |
            Select-Object -First 1

          if ($latestHealthyNode) {
            return $latestHealthyNode
          }
        }
      }
      catch {
      }
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for server runtime policy status for client '$ClientName'."
}

$results = New-Object System.Collections.Generic.List[object]
$localServerIp = $null
$effectiveServerPort = $null
$runStartedUtc = (Get-Date).ToUniversalTime()

$results.Add((Invoke-And-Capture -Name "01-verify-required-paths" -Action {
  foreach ($requiredPath in @(
    $installRealServerScript,
    $startRealServerScript,
    $serverBuildExe,
    $serverPolicyScript,
    $macBuildRolloutScript,
    $macInstallRolloutScript,
    $macInspectStateScript,
    $macConnectivityScript,
    $macInfoPlistPath
  )) {
    if (-not (Test-Path $requiredPath)) {
      throw "Required path was not found: $requiredPath"
    }
    Write-Host "Found $requiredPath"
  }
}))

$results.Add((Invoke-And-Capture -Name "02-start-local-server-service" -Action {
  $existingService = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if ($existingService -and $existingService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $stopRealServerScript
  }

  & powershell -NoProfile -ExecutionPolicy Bypass -File $installRealServerScript

  $script:localServerIp = Get-LanIPv4
  $script:effectiveServerPort = Resolve-AvailableServerPort -PreferredPort $ServerPort

  if (-not (Test-Path $settingsPath)) {
    throw "Server settings file was not found at $settingsPath"
  }

  [xml]$doc = Get-Content $settingsPath
  Set-XmlSetting -Document $doc -Name "IP" -Value $script:localServerIp
  Set-XmlSetting -Document $doc -Name "Port" -Value $script:effectiveServerPort.ToString()
  $doc.Save($settingsPath)

  & $serverPolicyScript `
    -Enable `
    -ServerId $env:COMPUTERNAME `
    -PopupTheme "Modern" `
    -PopupPosition "BottomRight" `
    -AllowSound:$true `
    -NotificationSound "Chime" `
    -PlayAlertSound:$false `
    -PlayResponseSound:$false `
    -PinToTray:$true `
    -RunOnStartup:$true `
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

  $firewallRuleName = "Duress Alert Local Mac Rollout $($script:effectiveServerPort)"
  if (-not (Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Protocol TCP -LocalPort $script:effectiveServerPort -Action Allow | Out-Null
  }

  $service = Get-Service -Name "DuressAlertService"
  if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
    Restart-Service -Name "DuressAlertService"
  }
  else {
    Start-Service -Name "DuressAlertService"
  }

  (Get-Service -Name "DuressAlertService").WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))

  Write-Host "Configured local server IP: $script:localServerIp"
  Write-Host "Configured local server port: $script:effectiveServerPort"
  Test-NetConnection $script:localServerIp -Port $script:effectiveServerPort | Select-Object ComputerName, RemotePort, TcpTestSucceeded | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "03-configure-local-server-for-mac" -Action {
  if (-not $script:localServerIp) {
    throw "Local server IP was not initialized."
  }
  if (-not $script:effectiveServerPort) {
    throw "Local server port was not initialized."
  }

  Get-Service -Name "DuressAlertService" | Select-Object Name, Status, StartType | Format-Table -AutoSize
  Get-NetTCPConnection -State Listen -LocalPort $script:effectiveServerPort -ErrorAction Stop | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "04-export-local-provisioning-bundle" -Action {
  Export-LocalProvisioningBundle -BundlePath $localBundlePath -ClientName $MacClientName
  Get-Item $localBundlePath | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}))

$results.Add((Invoke-And-Capture -Name "05-ship-bundle-to-mac" -Action {
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "mkdir -p ${remoteBundleDir}",
    "mkdir -p ${RemoteMacRepoRoot}/scripts",
    "mkdir -p ${RemoteMacRepoRoot}/DuressAlertMac/DuressAlert"
  ) | Out-Null

  scp $macBuildRolloutScript "${MacHost}:${RemoteMacRepoRoot}/scripts/build-mac-rollout-package.sh" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy build-mac-rollout-package.sh to $MacHost."
  }

  scp $macInstallRolloutScript "${MacHost}:${RemoteMacRepoRoot}/scripts/install-mac-rollout-package.sh" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy install-mac-rollout-package.sh to $MacHost."
  }

  scp $macInfoPlistPath "${MacHost}:${RemoteMacRepoRoot}/DuressAlertMac/DuressAlert/Info.plist" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy Info.plist to $MacHost."
  }

  scp $localBundlePath "${MacHost}:${remoteBundleDir}/DuressClientProvisioningBundle.zip" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local provisioning bundle to $MacHost."
  }

  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "chmod +x ${RemoteMacRepoRoot}/scripts/build-mac-rollout-package.sh",
    "chmod +x ${RemoteMacRepoRoot}/scripts/install-mac-rollout-package.sh",
    "ls -l ${remoteBundleDir}"
  )
}))

$results.Add((Invoke-And-Capture -Name "06-build-remote-mac-rollout-pack" -Action {
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "if [ -d /opt/homebrew/opt/dotnet@8/libexec ]; then",
    "  export DOTNET_ROOT=/opt/homebrew/opt/dotnet@8/libexec",
    '  export PATH=/opt/homebrew/opt/dotnet@8/bin:$PATH',
    "fi",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/build-mac-rollout-package.sh --provisioning-bundle ${remoteBundleDir}/DuressClientProvisioningBundle.zip --runtime ${MacRuntimeIdentifier} --package-name ${remotePackageName} --output-root ${remoteBundleDir}"
  )
}))

$results.Add((Invoke-And-Capture -Name "07-install-and-launch-on-mac" -Action {
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${remoteBundleDir}/${remotePackageName}",
    "bash ./Install-DuressAlertMacWithProvisioning.sh --fresh-state --connect-on-launch"
  )
}))

$results.Add((Invoke-And-Capture -Name "08-verify-mac-state" -Action {
  Start-Sleep -Seconds 18
  Invoke-RemoteBashScript -Lines @(
    "set -euo pipefail",
    "cd ${RemoteMacRepoRoot}",
    "bash scripts/inspect-mac-client-state.sh",
    "echo ---",
    "bash scripts/probe-mac-connectivity-context.sh ${localServerIp} ${effectiveServerPort}"
  )
}))

$results.Add((Invoke-And-Capture -Name "09-verify-server-runtime-status" -Action {
  $node = Wait-ForServerRuntimeClient -ClientName $MacClientName -RunStartedUtc $runStartedUtc
  [pscustomobject]@{
    Name = $node.SelectSingleNode("Name").InnerText
    Version = $node.SelectSingleNode("LastPolicyVersion").InnerText
    Source = $node.SelectSingleNode("LastPolicySource").InnerText
    SignatureValid = $node.SelectSingleNode("LastSignatureValid").InnerText
    Error = $node.SelectSingleNode("LastPolicyError").InnerText
  } | Format-List
}))

$lines = @()
$lines += "# Local Server To Mac Rollout Regression"
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
$lines += "## Key outcomes"
$lines += ""
$lines += ('- Local Windows server service was configured to listen on `{0}:{1}`.' -f $localServerIp, $effectiveServerPort)
$lines += "- A fresh local `DuressClientProvisioningBundle.zip` was exported from the current server settings."
$lines += "- The bundle was copied to the Mac and packaged together with `DuressAlert.app` into a rollout-style Mac handoff."
$lines += "- The Mac install helper staged the bundle into `Provisioning/Pending`, relaunched the app, and requested live server policy."
$lines += "- Success requires both Mac-side policy/provisioning state and local server runtime policy status to go green."
$lines += ""
$lines += "## Artifacts"
$lines += ""
$lines += "- [Local provisioning bundle]($($localBundlePath -replace '\\','/'))"
$lines += ('- Remote Mac rollout root: `{0}/{1}`' -f $remoteBundleDir, $remotePackageName)

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) {
  throw ("Local server to Mac rollout regression completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}

Write-Host "Local server to Mac rollout regression written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
