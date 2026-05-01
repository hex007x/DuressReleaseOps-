Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildClientScript = Join-Path $scriptRoot "build-client.ps1"
$buildServerScript = Join-Path $scriptRoot "build-real-server.ps1"
$prepareSandboxScript = Join-Path $scriptRoot "prepare-sandbox.ps1"
$buildRoot = Join-Path $scriptRoot "build"
$latestPointer = Join-Path $buildRoot "latest-build.txt"
$releasesRoot = Join-Path $buildRoot "releases"
$serverExe = Join-Path $scriptRoot "server-build\DuressServer.exe"
$suiteRoot = Join-Path $scriptRoot "sandbox\policy-suite"
$suiteServerRoot = Join-Path $suiteRoot "server-data"
$suiteClientUserRoot = Join-Path $suiteRoot "client-user"
$suiteClientCommonRoot = Join-Path $suiteRoot "client-common"
$suiteArtifactsRoot = Join-Path $suiteRoot "artifacts"
$suiteHarnessScript = Join-Path $suiteArtifactsRoot "run-server-harness.ps1"
$suiteHarnessPidFile = Join-Path $suiteArtifactsRoot "server-harness.pid"
$suiteHarnessStatusFile = Join-Path $suiteArtifactsRoot "server-harness-status.txt"
$clientSettingsPath = Join-Path $suiteClientUserRoot "settings.json"
$clientLogPath = Join-Path $suiteClientUserRoot "DuressText.mdl"
$clientPolicyStatePath = Join-Path $suiteClientCommonRoot "policy-state.json"
$trustedKeyPath = Join-Path $suiteClientCommonRoot "trusted-server-policy-key.xml"
$emergencyUnlockPath = Join-Path $suiteClientCommonRoot "policy-emergency-unlock.xml"
$modernClientName = "Shared Test Client"

function Get-LatestClientExePath {
  if (Test-Path $latestPointer) {
    $latestBuild = (Get-Content $latestPointer -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($latestBuild) {
      $candidate = Join-Path $releasesRoot $latestBuild
      $candidateExe = Join-Path $candidate "Duress.exe"
      if (Test-Path $candidateExe) {
        return $candidateExe
      }
    }
  }

  if (Test-Path $releasesRoot) {
    $latestDir = Get-ChildItem -Path $releasesRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latestDir) {
      $candidateExe = Join-Path $latestDir.FullName "Duress.exe"
      if (Test-Path $candidateExe) {
        return $candidateExe
      }
    }
  }

  return $null
}

function Wait-ForFilePattern {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$TimeoutSeconds = 20
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      $content = Get-Content $Path -Raw
      if ($content -match $Pattern) {
        return $content
      }
    }

    Start-Sleep -Milliseconds 300
  }

  throw "Timed out waiting for pattern '$Pattern' in $Path"
}

function Wait-ForCondition {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Condition,
    [Parameter(Mandatory = $true)][string]$Description,
    [int]$TimeoutSeconds = 20
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }

    Start-Sleep -Milliseconds 300
  }

  throw "Timed out waiting for: $Description"
}

function Set-ClientServerPort {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][int]$Port
  )

  $json = Get-Content $Path -Raw | ConvertFrom-Json
  $json.SIP = "127.0.0.1"
  $json.SPort = $Port.ToString()
  $json | ConvertTo-Json | Set-Content -Path $Path
}

function Invoke-ServerReflection {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
  )

  $serverRootLiteral = $suiteServerRoot.Replace("'", "''")
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
  $serverRootLiteral = $suiteServerRoot.Replace("'", "''")
  $serverExeLiteral = $serverExe.Replace("'", "''")
  $statusFileLiteral = $suiteHarnessStatusFile.Replace("'", "''")
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

  Set-Content -Path $suiteHarnessScript -Value $harnessContent -Encoding ASCII
  $process = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $suiteHarnessScript) -PassThru
  Set-Content -Path $suiteHarnessPidFile -Value $process.Id -Encoding ASCII
  Wait-ForCondition -Description "isolated server harness start" -TimeoutSeconds 20 -Condition {
    if (-not (Test-Path $suiteHarnessStatusFile)) { return $false }
    $statusText = Get-Content $suiteHarnessStatusFile -Raw -ErrorAction SilentlyContinue
    if ($null -eq $statusText) { return $false }
    return $statusText.Trim() -eq "started"
  }
  return $process
}

function Stop-IsolatedServerHarness {
  if (Test-Path $suiteHarnessPidFile) {
    $pidValue = [int](Get-Content $suiteHarnessPidFile -Raw).Trim()
    try {
      $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
      if ($process) {
        Stop-Process -Id $pidValue -Force
      }
    } catch {}
  }
}

function Start-ModernClient {
  param(
    [Parameter(Mandatory = $true)][string]$ExePath
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ExePath
  $psi.WorkingDirectory = Split-Path -Parent $ExePath
  $psi.UseShellExecute = $false
  $psi.EnvironmentVariables["DURESS_USER_DATA_ROOT"] = $suiteClientUserRoot
  $psi.EnvironmentVariables["DURESS_COMMON_DATA_ROOT"] = $suiteClientCommonRoot
  $psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
  $psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = "policy-suite-modern"
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
      $Process.WaitForExit(3000) | Out-Null
    }
  } catch {}
}

function New-WireClient {
  param(
    [Parameter(Mandatory = $true)][string]$RegistrationLine,
    [string]$ServerHost = "127.0.0.1",
    [int]$Port = 8001
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  $client.Connect($ServerHost, $Port)
  $stream = $client.GetStream()
  $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII, 1024, $true)
  $writer.NewLine = "`n"
  $writer.AutoFlush = $true
  $writer.WriteLine($RegistrationLine)
  Start-Sleep -Milliseconds 150

  [pscustomobject]@{
    RegistrationLine = $RegistrationLine
    Name = ($RegistrationLine -split '\|')[0]
    Client = $client
    Stream = $stream
    Writer = $writer
  }
}

function Send-WireMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$Body
  )

  $payload = "{0}%{1}`${2}" -f $Client.Name, $Command, $Body
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
  $Client.Stream.Write($bytes, 0, $bytes.Length)
  $Client.Stream.Flush()
  return $payload
}

function Close-WireClient {
  param([Parameter(Mandatory = $true)]$Client)
  try { $Client.Writer.Dispose() } catch {}
  try { $Client.Stream.Dispose() } catch {}
  try { $Client.Client.Close() } catch {}
}

Remove-Item -Recurse -Force $suiteRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $suiteServerRoot, $suiteClientUserRoot, $suiteClientCommonRoot, $suiteArtifactsRoot | Out-Null

& $prepareSandboxScript
& $buildClientScript
& $buildServerScript

$clientExe = Get-LatestClientExePath
if (-not $clientExe) {
  throw "Could not find a built client executable."
}

Copy-Item (Join-Path $scriptRoot "sandbox\clients\client-a\user-data\settings.json") $clientSettingsPath -Force
Copy-Item (Join-Path $scriptRoot "sandbox\common-data\gSettings.json") (Join-Path $suiteClientCommonRoot "gSettings.json") -Force
Set-ClientServerPort -Path $clientSettingsPath -Port 8001

Invoke-ServerReflection {
  $configType = $asm.GetType('DuressAlert.ConfigManager')
  $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
  $ensure = $configType.GetMethod('EnsureClientPolicySigningKeys', [System.Reflection.BindingFlags]'Static,Public')
  $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
  $save = $configType.GetMethod('SaveSettings', [System.Reflection.BindingFlags]'Static,Public')
  $publicKeyField = $configType.GetField('ClientPolicyPublicKeyFile', [System.Reflection.BindingFlags]'Static,Public')
  $privateKeyField = $configType.GetField('ClientPolicyPrivateKeyFile', [System.Reflection.BindingFlags]'Static,Public')
  $ensure.Invoke($null, @())
  $settings = $load.Invoke($null, @())
  $serverSettingsType.GetProperty('PolicyEnabled').SetValue($settings, $true)
  $serverSettingsType.GetProperty('PolicyServerId').SetValue($settings, 'isolated-policy-server')
  $serverSettingsType.GetProperty('PolicyDefaultPopupTheme').SetValue($settings, 'Modern')
  $serverSettingsType.GetProperty('PolicyDefaultPopupPosition').SetValue($settings, 'Center')
  $serverSettingsType.GetProperty('PolicyAllowSound').SetValue($settings, $false)
  $serverSettingsType.GetProperty('PolicyLockPopupPosition').SetValue($settings, $true)
  $serverSettingsType.GetProperty('PolicyLockPopupTheme').SetValue($settings, $true)
  $save.Invoke($null, @($settings))
  Remove-Item -Force -ErrorAction SilentlyContinue $publicKeyField.GetValue($null), $privateKeyField.GetValue($null)
  $ensure.Invoke($null, @())
  $publicKeyField.GetValue($null)
}

$serverPublicKeySource = Join-Path $suiteServerRoot "TrustedServerPolicyKey.xml"
Copy-Item $serverPublicKeySource $trustedKeyPath -Force

$serverHarness = $null
$modernClient = $null
$legacyClient = $null

try {
  $serverHarness = Start-IsolatedServerHarness

  $modernClient = Start-ModernClient -ExePath $clientExe
  $modernLog = Wait-ForFilePattern -Path $clientLogPath -Pattern "Applied signed server policy v1 from isolated-policy-server \(server\)\." -TimeoutSeconds 25
  Wait-ForCondition -Description "client policy state file" -TimeoutSeconds 15 -Condition { Test-Path $clientPolicyStatePath }
  $policyState = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json

  Wait-ForCondition -Description "server runtime status with reported policy state" -TimeoutSeconds 15 -Condition {
    if (-not (Test-Path (Join-Path $suiteServerRoot "LicenseRuntimeStatus.xml"))) { return $false }
    $xml = [xml](Get-Content (Join-Path $suiteServerRoot "LicenseRuntimeStatus.xml"))
    $node = $xml.SelectSingleNode("/LicenseRuntimeStatus/Clients/Client[Name='Shared Test Client']")
    return $null -ne $node -and $node.LastPolicyVersion -eq "1"
  }

  Invoke-ServerReflection {
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $actionType = $asm.GetType('DuressAlert.PendingClientAdminAction')
    $queue = $configType.GetMethod('QueuePendingClientAdminAction', [System.Reflection.BindingFlags]'Static,Public')
    $action = [Activator]::CreateInstance($actionType)
    $actionType.GetProperty('ActionType').SetValue($action, 'ResendPolicy')
    $actionType.GetProperty('ClientName').SetValue($action, 'Shared Test Client')
    $actionType.GetProperty('RequestedUtc').SetValue($action, [DateTime]::UtcNow)
    $queue.Invoke($null, @($action))
  }

  Wait-ForCondition -Description "queued resend processed" -TimeoutSeconds 20 -Condition {
    if (-not (Test-Path (Join-Path $suiteServerRoot "PendingClientAdminActions.xml"))) { return $true }
    $xml = [xml](Get-Content (Join-Path $suiteServerRoot "PendingClientAdminActions.xml"))
    return $xml.SelectNodes("/PendingClientAdminActions/Action").Count -eq 0
  }

  Wait-ForFilePattern -Path (Join-Path $suiteServerRoot ("Logs\DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd"))) -Pattern "Processed pending client admin action 'ResendPolicy'" -TimeoutSeconds 20 | Out-Null

  Stop-ProcessQuietly $modernClient
  $modernClient = $null

  Invoke-ServerReflection {
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $runtimeStatusFile = $configType.GetField('LicenseRuntimeStatusFile', [System.Reflection.BindingFlags]'Static,Public').GetValue($null)
    [xml]$runtime = Get-Content $runtimeStatusFile
    $node = @($runtime.LicenseRuntimeStatus.Clients.Client | Where-Object { $_.Name -eq 'Shared Test Client' })[0]
    if ($null -eq $node) { throw 'Could not find runtime client entry for the modern policy test client.' }
    $clientType = $asm.GetType('DuressAlert.ClientRuntimeInfo')
    $client = [Activator]::CreateInstance($clientType)
    $clientType.GetProperty('Name').SetValue($client, $node.Name)
    $clientType.GetProperty('InstallationId').SetValue($client, $node.InstallationId)
    $clientType.GetProperty('MachineName').SetValue($client, $node.MachineName)
    $settingsFormType = $asm.GetType('DuressAlert.SettingsForm')
    $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
    $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $settings = $load.Invoke($null, @())
    $serverSettingsType.GetProperty('PolicyServerId').SetValue($settings, 'isolated-policy-server')
    $settingsForm = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject($settingsFormType)
    $settingsFormType.GetField('settings', [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($settingsForm, $settings)
    $build = $settingsFormType.GetMethod('BuildSignedOfflinePolicyUnlockEnvelope', [System.Reflection.BindingFlags]'Instance,NonPublic')
    $build.Invoke($settingsForm, @($client, [TimeSpan]::FromHours(1)))
  } | Set-Content -Path $emergencyUnlockPath -Encoding UTF8

  if (Test-Path $clientLogPath) {
    Remove-Item $clientLogPath -Force
  }

  $modernClient = Start-ModernClient -ExePath $clientExe
  Wait-ForFilePattern -Path $clientLogPath -Pattern "Emergency local unlock active until" -TimeoutSeconds 20 | Out-Null
  $unlockLog = Wait-ForFilePattern -Path $clientLogPath -Pattern "Ignored server policy from server: emergency local unlock is active until" -TimeoutSeconds 20
  $policyStateAfterUnlock = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json

  $legacyClient = New-WireClient -RegistrationLine "Legacy Policy Compatibility|version=0.9.0.0|platform=Windows"
  Send-WireMessage -Client $legacyClient -Command "Alert" -Body "Legacy compatibility alert" | Out-Null
  Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null

  [pscustomobject]@{
    Suite = "ClientPolicy"
    ModernClientPolicyApplied = $modernLog -match "Applied signed server policy"
    ReportedPolicyVersion = $policyState.LastPolicyVersion
    ReportedPolicyValid = [bool]$policyState.LastSignatureValid
    PendingResendProcessed = $true
    EmergencyUnlockApplied = $unlockLog -match "Emergency local unlock active"
    PolicyStateAfterUnlock = [pscustomobject]@{
      LastPolicyVersion = $policyStateAfterUnlock.LastPolicyVersion
      LastSignatureValid = $policyStateAfterUnlock.LastSignatureValid
      LastError = $policyStateAfterUnlock.LastError
    }
    LegacyCompatibility = "Legacy client remained on the classic wire flow while the modern client still received alerts."
    Recommendation = "Run this suite alongside exercise-compatibility-suite.ps1 when changing policy, monitor, or legacy-wire behavior."
  } | Format-List
}
finally {
  if ($legacyClient) {
    Close-WireClient -Client $legacyClient
  }

  Stop-ProcessQuietly $modernClient
  Stop-IsolatedServerHarness
}
