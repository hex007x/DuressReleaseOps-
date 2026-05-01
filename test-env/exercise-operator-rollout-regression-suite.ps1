param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\operator-rollout-regression\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$ClientMsiPath = "",
  [switch]$UseCloudClaim,
  [switch]$FetchInstallersFromCloud,
  [switch]$FetchServerInstallerFromCloud,
  [string]$CloudSystemName = "Main Reception Server",
  [string]$ClaimToken = "DEV-CLAIM-DEFAULT",
  [string]$CloudPortalUrl = "http://localhost:5186",
  [string]$CloudClaimUrl = "http://localhost:5186/api/systems/claim",
  [string]$CloudCheckinUrl = "http://localhost:5186/api/licensing/checkin",
  [string]$CloudLicenseApiToken = "",
  [string]$DatabaseName = "duress_cloud_dev",
  [string]$DatabaseUser = "duress_app",
  [string]$DatabasePassword = "DuressCloudLocal!2026",
  [string]$PsqlPath = "C:\\Program Files\\PostgreSQL\\16\\bin\\psql.exe"
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
$downloadsRoot = Join-Path $OutputRoot "downloads"
$serverDataRoot = Join-Path $OutputRoot "server-data"
$serverHarnessScript = Join-Path $OutputRoot "run-server-harness.ps1"
$serverHarnessPidFile = Join-Path $OutputRoot "server-harness.pid"
$serverHarnessStatusFile = Join-Path $OutputRoot "server-harness-status.txt"
$clientUserRoot = Join-Path $env:APPDATA "Duress Alert"
$clientCommonRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) "Duress Alert"
$clientPendingRoot = Join-Path $clientCommonRoot "Provisioning\Pending"
$clientPolicyStatePath = Join-Path $clientCommonRoot "policy-state.json"
$clientPolicyKeyPath = Join-Path $clientCommonRoot "trusted-server-policy-key.xml"
$clientServerSettingsPath = Join-Path $clientCommonRoot "settings.json"
$clientGeneralSettingsPath = Join-Path $clientCommonRoot "gSettings.json"
$clientLogPath = Join-Path $clientUserRoot "DuressText.mdl"
$summaryPath = Join-Path $OutputRoot "OPERATOR_ROLLOUT_REGRESSION_SUMMARY.md"
$serverLicensePath = Join-Path $serverDataRoot "License.dat"
$serverUpdateKitDir = Join-Path $serverDataRoot "ProvisioningArtifacts\\ServerUpdateKits"

if ($FetchInstallersFromCloud) {
  $UseCloudClaim = $true
}

if (-not $FetchInstallersFromCloud -and [string]::IsNullOrWhiteSpace($ClientMsiPath)) {
  $releaseRoot = Join-Path $workspaceRoot "Duress2025\Duress.Installer\Release"
  $latestMsi = Get-ChildItem -Path $releaseRoot -Filter "Duress.Alert.Client*.msi" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

  if ($latestMsi) {
    $ClientMsiPath = $latestMsi.FullName
  }
}

if (-not $FetchInstallersFromCloud -and -not (Test-Path $ClientMsiPath)) {
  throw "Client MSI not found at $ClientMsiPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot, $shotsRoot, $downloadsRoot, $serverDataRoot | Out-Null

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

function Wait-ForFilePattern {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$TimeoutSeconds = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      $content = Get-Content $Path -Raw
      if ($content -match $Pattern) {
        return $content
      }
    }

    Start-Sleep -Milliseconds 400
  }

  throw "Timed out waiting for pattern '$Pattern' in $Path"
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

function Seed-IsolatedServerLicense {
  $licenseLines = @(
    "DUALERT-DEMO-MODE"
    "Full"
    "2099-01-01T00:00:00Z"
  )

  Set-Content -Path $serverLicensePath -Value $licenseLines -Encoding ASCII
}

function Get-CloudClaimTokenHash {
  param([Parameter(Mandatory = $true)][string]$Token)

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Token))
    return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
  }
  finally {
    $sha256.Dispose()
  }
}

function Invoke-CloudSql {
  param([Parameter(Mandatory = $true)][string]$Sql)

  if (-not (Test-Path $PsqlPath)) {
    throw "psql.exe was not found at $PsqlPath"
  }

  $sqlPath = Join-Path $OutputRoot ("cloud-sql-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
  Set-Content -Path $sqlPath -Value $Sql -Encoding UTF8
  $previousPassword = $env:PGPASSWORD
  try {
    $env:PGPASSWORD = $DatabasePassword
    $output = & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F "|" -f $sqlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw ("psql query failed: " + ($output | Out-String).Trim())
    }
    return (($output | Out-String).Trim() -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  }
  finally {
    $env:PGPASSWORD = $previousPassword
    Remove-Item -LiteralPath $sqlPath -Force -ErrorAction SilentlyContinue
  }
}

function Prepare-CloudClaimToken {
  $hash = Get-CloudClaimTokenHash -Token $ClaimToken
  $escapedSystemName = $CloudSystemName.Replace("'", "''")
  $sql = @"
update "SystemInstallations"
set "ClaimTokenHash" = '$hash',
    "ServerFingerprint" = 'pending-operator-rollout-claim',
    "LastSeenMachineId" = '',
    "LocalIpLastSeen" = '',
    "PublicIpLastSeen" = '',
    "CheckinCount" = 0,
    "LastCheckinResult" = 'Pending operator rollout regression claim'
where "SystemName" = '$escapedSystemName';

select "SystemName", "ClaimTokenHash"
from "SystemInstallations"
where "SystemName" = '$escapedSystemName';
"@

  $rows = Invoke-CloudSql -Sql $sql
  if (-not $rows -or $rows.Count -lt 1) {
    throw "Could not prepare the linked-cloud claim token for system '$CloudSystemName'."
  }
}

function Invoke-ConfigureCloudLinkSettings {
  $portalLiteral = $CloudPortalUrl.Replace("'", "''")
  $claimLiteral = $CloudClaimUrl.Replace("'", "''")
  $checkinLiteral = $CloudCheckinUrl.Replace("'", "''")
  $claimTokenLiteral = $ClaimToken.Replace("'", "''")
  $licenseApiLiteral = $CloudLicenseApiToken.Replace("'", "''")

  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
    $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $save = $configType.GetMethod('SaveSettings', [System.Reflection.BindingFlags]'Static,Public')
    $settings = $load.Invoke($null, @())
    $serverSettingsType.GetProperty('LicensePortalUrl').SetValue($settings, '__PORTAL_URL__')
    $serverSettingsType.GetProperty('CloudClaimUrl').SetValue($settings, '__CLAIM_URL__')
    $serverSettingsType.GetProperty('CloudCheckinUrl').SetValue($settings, '__CHECKIN_URL__')
    $serverSettingsType.GetProperty('CloudClaimToken').SetValue($settings, '__CLAIM_TOKEN__')
    $serverSettingsType.GetProperty('LicenseApiToken').SetValue($settings, '__LICENSE_API_TOKEN__')
    $save.Invoke($null, @($settings))
'@

  $scriptText = $scriptText.Replace('__PORTAL_URL__', $portalLiteral)
  $scriptText = $scriptText.Replace('__CLAIM_URL__', $claimLiteral)
  $scriptText = $scriptText.Replace('__CHECKIN_URL__', $checkinLiteral)
  $scriptText = $scriptText.Replace('__CLAIM_TOKEN__', $claimTokenLiteral)
  $scriptText = $scriptText.Replace('__LICENSE_API_TOKEN__', $licenseApiLiteral)
  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
}

function Invoke-ClaimCloudLicense {
  $scriptText = @'
    $settings = [DuressAlert.ConfigManager]::LoadSettings()
    $response = $null
    $message = ''
    $ok = [DuressAlert.LicenseManager]::TryClaimCloudSystem($settings, [ref]$response, [ref]$message)
    $runtime = [DuressAlert.ConfigManager]::LoadLicenseRuntimeStatus()
    $runtime.GetType().GetProperty('LastCloudCheckUtc').SetValue($runtime, [DateTime]::UtcNow)
    $runtime.GetType().GetProperty('LastCloudCheckResult').SetValue($runtime, $message)
    $runtime.GetType().GetProperty('LastCloudLicenseState').SetValue($runtime, '__CLOUD_STATE__')
    [DuressAlert.ConfigManager]::SaveLicenseRuntimeStatus($runtime)
    if (-not $ok) {
      throw [System.InvalidOperationException]::new($message)
    }
'@

  $scriptText = $scriptText.Replace('__CLOUD_STATE__', 'Claimed')
  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
}

function Invoke-FetchInstallerFromCloud {
  param([Parameter(Mandatory = $true)][bool]$ServerInstaller)

  $scriptText = @'
    $settings = [DuressAlert.ConfigManager]::LoadSettings()
    $license = [DuressAlert.LicenseManager]::GetLicenseInfo()
    if ($license -eq $null -or -not $license.IsValid -or [string]::IsNullOrWhiteSpace($license.LicenseId)) {
      throw [System.InvalidOperationException]::new('No active signed license was available for the cloud installer fetch.')
    }
    $downloadUrl = [DuressAlert.LicenseManager]::BuildCloudInstallerDownloadUrlFromPortalUrl($settings.LicensePortalUrl)
    if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
      throw [System.InvalidOperationException]::new('The portal URL did not resolve to a cloud installer download endpoint.')
    }

    [pscustomobject]@{
      LicenseSerial = $license.LicenseId
      ServerFingerprint = [DuressAlert.LicenseManager]::GetServerFingerprint()
      PackageType = '__PACKAGE_TYPE__'
      DownloadUrl = $downloadUrl
      LicenseApiToken = $settings.LicenseApiToken
    } | ConvertTo-Json -Compress
'@

  $scriptText = $scriptText.Replace('__PACKAGE_TYPE__', $(if ($ServerInstaller) { 'Server' } else { 'Client' }))
  $contextJson = Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
  $context = ($contextJson | Out-String | ConvertFrom-Json)

  $tempFile = Join-Path $downloadsRoot ($(if ($ServerInstaller) { 'cloud-fetched-server.msi' } else { 'cloud-fetched-client.msi' }))
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($context.LicenseApiToken)) {
    $headers["X-Duress-License-Token"] = [string]$context.LicenseApiToken
  }

  try {
    Invoke-WebRequest -Uri $context.DownloadUrl -Method Post -Body ($context | Select-Object LicenseSerial, ServerFingerprint, PackageType | ConvertTo-Json -Compress) -ContentType "application/json" -Headers $headers -OutFile $tempFile -UseBasicParsing | Out-Null
  }
  catch {
    if ($_.Exception.Response) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      try {
        $responseText = $reader.ReadToEnd()
      }
      finally {
        $reader.Dispose()
      }
      throw "Cloud installer fetch failed: $responseText"
    }
    throw
  }

  $importMethodName = if ($ServerInstaller) { "ImportCachedServerInstaller" } else { "ImportCachedClientInstaller" }
  $importScript = @'
    $cachedPath = [DuressAlert.ProvisionedInstallerPackageBuilder]::__METHOD_NAME__('__TEMP_FILE__')
    Write-Output $cachedPath
'@

  $importScript = $importScript.Replace('__METHOD_NAME__', $importMethodName)
  $importScript = $importScript.Replace('__TEMP_FILE__', $tempFile.Replace("'", "''"))
  $cachedPath = Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($importScript))
  return ($cachedPath | Out-String).Trim()
}

function Get-CachedInstallerPath {
  param([Parameter(Mandatory = $true)][bool]$ServerInstaller)

  $methodName = if ($ServerInstaller) { "GetCachedServerInstallerPath" } else { "GetCachedClientInstallerPath" }
  $scriptText = @'
    $packageBuilderType = $asm.GetType('DuressAlert.ProvisionedInstallerPackageBuilder')
    $path = $packageBuilderType.GetMethod('__METHOD_NAME__', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @())
    Write-Output $path
'@

  $scriptText = $scriptText.Replace('__METHOD_NAME__', $methodName)
  return ((Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))) | Out-String).Trim()
}

function Invoke-ExportServerUpdateKit {
  param([Parameter(Mandatory = $true)][string]$Label)

  $kitName = "DuressServerUpdateKit-$Label.zip"
  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $packageBuilderType = $asm.GetType('DuressAlert.ProvisionedInstallerPackageBuilder')
    $updateDir = $configType.GetField('ServerUpdateKitOutputDir', [System.Reflection.BindingFlags]'Static,Public').GetValue($null)
    [System.IO.Directory]::CreateDirectory($updateDir) | Out-Null
    $cachedServer = $packageBuilderType.GetMethod('GetCachedServerInstallerPath', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @())
    if ([string]::IsNullOrWhiteSpace($cachedServer) -or -not [System.IO.File]::Exists($cachedServer)) {
      throw [System.IO.FileNotFoundException]::new('A cached server MSI is required before the update kit can be exported.', $cachedServer)
    }
    $outputPath = [System.IO.Path]::Combine($updateDir, '__KIT_NAME__')
    $packageBuilderType.GetMethod('ExportServerUpdateKit', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @($outputPath, $cachedServer))
'@

  $scriptText = $scriptText.Replace('__KIT_NAME__', $kitName)
  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
  return $kitName
}

function Invoke-PolicyProfileSave {
  param(
    [Parameter(Mandatory = $true)][string]$PopupTheme,
    [Parameter(Mandatory = $true)][string]$PopupPosition,
    [Parameter(Mandatory = $true)][bool]$AllowSound,
    [Parameter(Mandatory = $true)][string]$NotificationSound,
    [Parameter(Mandatory = $true)][bool]$PlayAlertSound,
    [Parameter(Mandatory = $true)][bool]$PlayResponseSound,
    [Parameter(Mandatory = $true)][bool]$RunOnStartup,
    [Parameter(Mandatory = $true)][bool]$PinToTray,
    [Parameter(Mandatory = $true)][bool]$EscalationEnabled,
    [Parameter(Mandatory = $true)][int]$EscalationDelaySeconds
  )

  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $serverSettingsType = $asm.GetType('DuressAlert.ServerSettings')
    $ensure = $configType.GetMethod('EnsureClientPolicySigningKeys', [System.Reflection.BindingFlags]'Static,Public')
    $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $save = $configType.GetMethod('SaveSettings', [System.Reflection.BindingFlags]'Static,Public')
    $ensureFolders = $configType.GetMethod('EnsureFoldersExist', [System.Reflection.BindingFlags]'Static,Public')
    $ensureFolders.Invoke($null, @())
    $ensure.Invoke($null, @())
    $settings = $load.Invoke($null, @())
    $serverSettingsType.GetProperty('IP').SetValue($settings, [System.Net.IPAddress]::Any)
    $serverSettingsType.GetProperty('Port').SetValue($settings, 8001)
    $serverSettingsType.GetProperty('PolicyEnabled').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyServerId').SetValue($settings, 'operator-rollout-server')
    $serverSettingsType.GetProperty('PolicyDefaultPopupTheme').SetValue($settings, '__POPUP_THEME__')
    $serverSettingsType.GetProperty('PolicyDefaultPopupPosition').SetValue($settings, '__POPUP_POSITION__')
    $serverSettingsType.GetProperty('PolicyAllowSound').SetValue($settings, __ALLOW_SOUND__)
    $serverSettingsType.GetProperty('PolicyDefaultNotificationSound').SetValue($settings, '__NOTIFICATION_SOUND__')
    $serverSettingsType.GetProperty('PolicyDefaultPlayAlertSound').SetValue($settings, __PLAY_ALERT__)
    $serverSettingsType.GetProperty('PolicyDefaultPlayResponseSound').SetValue($settings, __PLAY_RESPONSE__)
    $serverSettingsType.GetProperty('PolicyDefaultRunOnStartup').SetValue($settings, __RUN_ON_STARTUP__)
    $serverSettingsType.GetProperty('PolicyDefaultPinToTray').SetValue($settings, __PIN_TO_TRAY__)
    $serverSettingsType.GetProperty('PolicyDefaultEscalationEnabled').SetValue($settings, __ESCALATION_ENABLED__)
    $serverSettingsType.GetProperty('PolicyDefaultEscalationDelaySeconds').SetValue($settings, __ESCALATION_DELAY__)
    $serverSettingsType.GetProperty('PolicyLockPopupTheme').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyLockPopupPosition').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyLockSoundAllowed').SetValue($settings, $true)
    $serverSettingsType.GetProperty('PolicyLockNotificationSound').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockPlayAlertSound').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockPlayResponseSound').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockPinToTray').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockRunOnStartup').SetValue($settings, $false)
    $serverSettingsType.GetProperty('PolicyLockEscalation').SetValue($settings, $false)
    $save.Invoke($null, @($settings))
'@

  $scriptText = $scriptText.Replace('__POPUP_THEME__', $PopupTheme.Replace("'", "''"))
  $scriptText = $scriptText.Replace('__POPUP_POSITION__', $PopupPosition.Replace("'", "''"))
  $scriptText = $scriptText.Replace('__ALLOW_SOUND__', $(if ($AllowSound) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__NOTIFICATION_SOUND__', $NotificationSound.Replace("'", "''"))
  $scriptText = $scriptText.Replace('__PLAY_ALERT__', $(if ($PlayAlertSound) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__PLAY_RESPONSE__', $(if ($PlayResponseSound) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__RUN_ON_STARTUP__', $(if ($RunOnStartup) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__PIN_TO_TRAY__', $(if ($PinToTray) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__ESCALATION_ENABLED__', $(if ($EscalationEnabled) { '$true' } else { '$false' }))
  $scriptText = $scriptText.Replace('__ESCALATION_DELAY__', $EscalationDelaySeconds.ToString())
  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
}

function Get-ExpectedClientFacingServerIp {
  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $bundleBuilderType = $asm.GetType('DuressAlert.ClientProvisioningBundleBuilder')
    $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $settings = $load.Invoke($null, @())
    $bundleBuilderType.GetMethod('GetClientFacingServerIp', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @($settings))
'@

  $ip = Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))
  return ($ip | Out-String).Trim()
}

function Invoke-ExportRolloutArtifacts {
  param(
    [Parameter(Mandatory = $true)][string]$Label
  )

  $bundleName = "DuressClientProvisioningBundle-$Label.zip"
  $workPackageName = "DuressClientDeploymentPackage-workstation-$Label.zip"
  $terminalPackageName = "DuressClientDeploymentPackage-terminal-$Label.zip"
  $workMsiName = "Duress.Alert.Client-workstation-provisioned-$Label.msi"
  $terminalMsiName = "Duress.Alert.Client-terminal-provisioned-$Label.msi"

  $effectiveClientMsiPath = if ($FetchInstallersFromCloud) { Get-CachedInstallerPath -ServerInstaller:$false } else { $ClientMsiPath }
  if ([string]::IsNullOrWhiteSpace($effectiveClientMsiPath) -or -not (Test-Path $effectiveClientMsiPath)) {
    throw "A base client MSI is required before rollout artifacts can be exported."
  }

  $baseClientMsiLiteral = $effectiveClientMsiPath.Replace("'", "''")

  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $optionsType = $asm.GetType('DuressAlert.ClientProvisioningBundleOptions')
    $bundleBuilderType = $asm.GetType('DuressAlert.ClientProvisioningBundleBuilder')
    $packageBuilderType = $asm.GetType('DuressAlert.ProvisionedInstallerPackageBuilder')
    $load = $configType.GetMethod('LoadSettings', [System.Reflection.BindingFlags]'Static,Public')
    $bundleDir = $configType.GetField('ProvisioningBundleOutputDir', [System.Reflection.BindingFlags]'Static,Public').GetValue($null)
    $packageDir = $configType.GetField('ClientPackageOutputDir', [System.Reflection.BindingFlags]'Static,Public').GetValue($null)
    $customMsiDir = $configType.GetField('ClientCustomMsiOutputDir', [System.Reflection.BindingFlags]'Static,Public').GetValue($null)
    [System.IO.Directory]::CreateDirectory($bundleDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($packageDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($customMsiDir) | Out-Null
    $settings = $load.Invoke($null, @())

    $bundleOptions = [Activator]::CreateInstance($optionsType)
    $optionsType.GetProperty('Settings').SetValue($bundleOptions, $settings)
    $optionsType.GetProperty('SuggestedClientName').SetValue($bundleOptions, 'Operator Rollout Client')

    $terminalOptions = [Activator]::CreateInstance($optionsType)
    $optionsType.GetProperty('Settings').SetValue($terminalOptions, $settings)
    $optionsType.GetProperty('TerminalInstall').SetValue($terminalOptions, $true)
    $optionsType.GetProperty('SuggestedClientName').SetValue($terminalOptions, 'Operator Rollout Terminal')

    $bundleBuilderType.GetMethod('ExportBundle', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @([System.IO.Path]::Combine($bundleDir, '__BUNDLE_NAME__'), $bundleOptions))
    $packageBuilderType.GetMethod('ExportProvisionedClientDeploymentPackage', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @([System.IO.Path]::Combine($packageDir, '__WORK_PACKAGE_NAME__'), '__BASE_CLIENT_MSI__', $bundleOptions))
    $packageBuilderType.GetMethod('ExportProvisionedClientDeploymentPackage', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @([System.IO.Path]::Combine($packageDir, '__TERMINAL_PACKAGE_NAME__'), '__BASE_CLIENT_MSI__', $terminalOptions))
    $packageBuilderType.GetMethod('ExportProvisionedClientCustomMsi', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @([System.IO.Path]::Combine($customMsiDir, '__WORK_MSI_NAME__'), '__BASE_CLIENT_MSI__', $bundleOptions))
    $packageBuilderType.GetMethod('ExportProvisionedClientCustomMsi', [System.Reflection.BindingFlags]'Static,Public').Invoke($null, @([System.IO.Path]::Combine($customMsiDir, '__TERMINAL_MSI_NAME__'), '__BASE_CLIENT_MSI__', $terminalOptions))
'@

  $scriptText = $scriptText.Replace('__BUNDLE_NAME__', $bundleName)
  $scriptText = $scriptText.Replace('__WORK_PACKAGE_NAME__', $workPackageName)
  $scriptText = $scriptText.Replace('__TERMINAL_PACKAGE_NAME__', $terminalPackageName)
  $scriptText = $scriptText.Replace('__WORK_MSI_NAME__', $workMsiName)
  $scriptText = $scriptText.Replace('__TERMINAL_MSI_NAME__', $terminalMsiName)
  $scriptText = $scriptText.Replace('__BASE_CLIENT_MSI__', $baseClientMsiLiteral)
  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText))

  return [pscustomobject]@{
    BundleFileName = $bundleName
    WorkstationPackageFileName = $workPackageName
    TerminalPackageFileName = $terminalPackageName
    WorkstationMsiFileName = $workMsiName
    TerminalMsiFileName = $terminalMsiName
  }
}

function Invoke-QueuePolicyResend {
  param(
    [Parameter(Mandatory = $true)][string]$ClientName
  )

  $scriptText = @'
    $configType = $asm.GetType('DuressAlert.ConfigManager')
    $actionType = $asm.GetType('DuressAlert.PendingClientAdminAction')
    $queue = $configType.GetMethod('QueuePendingClientAdminAction', [System.Reflection.BindingFlags]'Static,Public')
    $action = [Activator]::CreateInstance($actionType)
    $actionType.GetProperty('ActionType').SetValue($action, 'ResendPolicy')
    $actionType.GetProperty('ClientName').SetValue($action, '__CLIENT_NAME__')
    $actionType.GetProperty('RequestedUtc').SetValue($action, [DateTime]::UtcNow)
    $queue.Invoke($null, @($action))
'@

  Invoke-ServerReflection -ScriptBlock ([scriptblock]::Create($scriptText.Replace('__CLIENT_NAME__', $ClientName.Replace("'", "''"))))
}

function Get-ArtifactLibraryUrl {
  return "http://127.0.0.1:8002/artifacts/"
}

function Invoke-DownloadHostedArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $downloadUrl = (Get-ArtifactLibraryUrl) + "download/" + [uri]::EscapeDataString($FileName)
  Invoke-WebRequest -Uri $downloadUrl -OutFile $DestinationPath -UseBasicParsing | Out-Null
}

function Assert-ClientConfig {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedServerIp,
    [Parameter(Mandatory = $true)][string]$ExpectedServerPort,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupTheme,
    [Parameter(Mandatory = $true)][string]$ExpectedPopupPosition,
    [Parameter(Mandatory = $true)][string]$ExpectedNotificationSound,
    [Parameter(Mandatory = $true)][bool]$ExpectedRunOnStartup,
    [Parameter(Mandatory = $true)][bool]$ExpectedPinToTray,
    [Parameter(Mandatory = $true)][bool]$ExpectedPlayAlertSound,
    [Parameter(Mandatory = $true)][bool]$ExpectedPlayResponseSound
  )

  if (-not (Test-Path $clientGeneralSettingsPath)) {
    throw "Client general settings were not found at $clientGeneralSettingsPath"
  }

  if (-not (Test-Path $clientServerSettingsPath)) {
    throw "Client server settings were not found at $clientServerSettingsPath"
  }

  $general = Get-Content $clientGeneralSettingsPath -Raw | ConvertFrom-Json
  $server = Get-Content $clientServerSettingsPath -Raw | ConvertFrom-Json

  if ($general.PopupTheme -ne $ExpectedPopupTheme) { throw "PopupTheme mismatch. Expected '$ExpectedPopupTheme', found '$($general.PopupTheme)'" }
  if ($general.PopupPosition -ne $ExpectedPopupPosition) { throw "PopupPosition mismatch. Expected '$ExpectedPopupPosition', found '$($general.PopupPosition)'" }
  if ($general.NotificationSound -ne $ExpectedNotificationSound) { throw "NotificationSound mismatch. Expected '$ExpectedNotificationSound', found '$($general.NotificationSound)'" }
  if ([bool]$general.ROS -ne $ExpectedRunOnStartup) { throw "RunOnStartup mismatch. Expected '$ExpectedRunOnStartup', found '$($general.ROS)'" }
  if ([bool]$general.Pin -ne $ExpectedPinToTray) { throw "Pin mismatch. Expected '$ExpectedPinToTray', found '$($general.Pin)'" }
  if ([bool]$general.PlayAlertSound -ne $ExpectedPlayAlertSound) { throw "PlayAlertSound mismatch. Expected '$ExpectedPlayAlertSound', found '$($general.PlayAlertSound)'" }
  if ([bool]$general.PlayResponseSound -ne $ExpectedPlayResponseSound) { throw "PlayResponseSound mismatch. Expected '$ExpectedPlayResponseSound', found '$($general.PlayResponseSound)'" }
  if ($server.SIP -ne $ExpectedServerIp) { throw "Server IP mismatch. Expected '$ExpectedServerIp', found '$($server.SIP)'" }
  if ($server.SPort -ne $ExpectedServerPort) { throw "Server port mismatch. Expected '$ExpectedServerPort', found '$($server.SPort)'" }
}

function Invoke-VerifyPolicyState {
  param(
    [Parameter(Mandatory = $true)][int]$MinimumPolicyVersion
  )

  Wait-ForCondition -Description "client policy state file" -TimeoutSeconds 25 -Condition {
    Test-Path $clientPolicyStatePath
  }

  $policyState = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
  if (-not $policyState.LastSignatureValid) {
    throw "Client policy state did not report a valid signature."
  }
  if ([int]$policyState.LastPolicyVersion -lt $MinimumPolicyVersion) {
    throw "Client policy version was lower than expected. Expected at least $MinimumPolicyVersion, found $($policyState.LastPolicyVersion)"
  }
  if (-not (Test-Path $clientPolicyKeyPath)) {
    throw "Trusted server policy key was not found at $clientPolicyKeyPath"
  }

  return $policyState
}

function Invoke-VerifyServerRuntimeClient {
  param(
    [Parameter(Mandatory = $true)][string]$ClientName,
    [Parameter(Mandatory = $true)][string]$ExpectedPolicyFingerprint,
    [int]$MinimumPolicyVersion = 1
  )

  $runtimeStatusPath = Join-Path $serverDataRoot "LicenseRuntimeStatus.xml"
  Wait-ForCondition -Description "server runtime status for managed client" -TimeoutSeconds 25 -Condition {
    if (-not (Test-Path $runtimeStatusPath)) { return $false }
    try {
      [xml]$runtime = Get-Content $runtimeStatusPath
      $node = $runtime.SelectSingleNode("/LicenseRuntimeStatus/Clients/Client[Name='$ClientName']")
      return $null -ne $node -and
        [int]$node.LastPolicyVersion -ge $MinimumPolicyVersion -and
        [string]$node.LastSignatureValid -eq "True" -and
        [string]$node.LastPolicyFingerprint -eq $ExpectedPolicyFingerprint
    }
    catch {
      return $false
    }
  }
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

function Remove-ClientPolicyResidue {
  foreach ($path in @(
    $clientPolicyStatePath,
    $clientPolicyKeyPath,
    $clientServerSettingsPath,
    $clientGeneralSettingsPath,
    $clientLogPath
  )) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }

  Remove-Item -LiteralPath (Join-Path $clientPendingRoot "DuressClientProvisioningBundle.zip") -Force -ErrorAction SilentlyContinue
}

$results = New-Object System.Collections.Generic.List[object]
$serverHarness = $null
$installedClientProcess = $null
$legacyClient = $null
$firstArtifacts = $null
$secondArtifacts = $null
$initialServerUpdateKit = ""
$updatedServerUpdateKit = ""
$expectedClientFacingServerIp = ""
$initialPolicyFingerprint = ""
$updatedPolicyFingerprint = ""

try {
  $results.Add((Invoke-And-Log -Name "01-build-server" -Action {
    & $msbuild $serverBuildProject /p:Configuration=Release /p:Platform=AnyCPU
    if ($LASTEXITCODE -ne 0) {
      throw "Server build failed."
    }
  }))

  $results.Add((Invoke-And-Log -Name "02-cleanup-client-before-suite" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $clientCleanupScript -IncludeInstallerCache
    Remove-ClientPolicyResidue
  }))

  $results.Add((Invoke-And-Log -Name "03-configure-initial-policy-profile" -Action {
    Invoke-PolicyProfileSave -PopupTheme "Modern" -PopupPosition "Center" -AllowSound:$false -NotificationSound "Chime" -PlayAlertSound:$false -PlayResponseSound:$false -RunOnStartup:$false -PinToTray:$true -EscalationEnabled:$true -EscalationDelaySeconds 90
    if ($UseCloudClaim) {
      Invoke-ConfigureCloudLinkSettings
      Prepare-CloudClaimToken
      Invoke-ClaimCloudLicense
      "Initial policy saved and cloud claim completed for the isolated operator-rollout server."
    }
    else {
      Seed-IsolatedServerLicense
      "Initial policy saved and demo/full license seeded for isolated rollout testing."
    }
  }))

  if ($FetchInstallersFromCloud) {
    $results.Add((Invoke-And-Log -Name "03b-fetch-approved-installers-from-cloud" -Action {
      $clientCachedPath = Invoke-FetchInstallerFromCloud -ServerInstaller:$false
      if (-not (Test-Path $clientCachedPath)) {
        throw "Client MSI fetch did not produce a cached MSI path."
      }

      $details = [System.Collections.Generic.List[string]]::new()
      $details.Add("Client MSI: $clientCachedPath") | Out-Null

      if ($FetchServerInstallerFromCloud) {
        $serverCachedPath = Invoke-FetchInstallerFromCloud -ServerInstaller:$true
        if (-not (Test-Path $serverCachedPath)) {
          throw "Server MSI fetch did not produce a cached MSI path."
        }
        $details.Add("Server MSI: $serverCachedPath") | Out-Null
      }

      $details
    }))
  }

  $results.Add((Invoke-And-Log -Name "03c-export-initial-rollout-artifacts" -Action {
    $script:expectedClientFacingServerIp = Get-ExpectedClientFacingServerIp
    $script:firstArtifacts = Invoke-ExportRolloutArtifacts -Label "initial"
    if ($FetchServerInstallerFromCloud) {
      $script:initialServerUpdateKit = Invoke-ExportServerUpdateKit -Label "initial"
    }
    [pscustomobject]@{
      ExpectedClientFacingServerIp = $script:expectedClientFacingServerIp
      BundleFileName = $script:firstArtifacts.BundleFileName
      WorkstationMsiFileName = $script:firstArtifacts.WorkstationMsiFileName
      TerminalMsiFileName = $script:firstArtifacts.TerminalMsiFileName
      ServerUpdateKitFileName = $script:initialServerUpdateKit
    } | Format-List
  }))

  $results.Add((Invoke-And-Log -Name "04-capture-deployment-wizard-screenshot" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-deployment-initial.png") -ServerDataRoot $serverDataRoot -StartupPage Deployment
  }))

  $results.Add((Invoke-And-Log -Name "05-start-isolated-server" -Action {
    $script:serverHarness = Start-IsolatedServerHarness
    "Isolated server harness started."
  }))

  $results.Add((Invoke-And-Log -Name "06-verify-hosted-artifact-library-and-downloads" -Action {
    $artifactUrl = Get-ArtifactLibraryUrl
    $indexPath = Join-Path $downloadsRoot "artifact-library.html"
    Invoke-WebRequest -Uri $artifactUrl -OutFile $indexPath -UseBasicParsing | Out-Null
    $indexContent = Get-Content $indexPath -Raw
    $expectedHostedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($fileName in @(
      $script:firstArtifacts.BundleFileName,
      $script:firstArtifacts.WorkstationPackageFileName,
      $script:firstArtifacts.TerminalPackageFileName,
      $script:firstArtifacts.WorkstationMsiFileName,
      $script:firstArtifacts.TerminalMsiFileName
    )) {
      $expectedHostedFiles.Add($fileName) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($script:initialServerUpdateKit)) {
      $expectedHostedFiles.Add($script:initialServerUpdateKit) | Out-Null
    }

    foreach ($fileName in $expectedHostedFiles) {
      if ($indexContent -notmatch [regex]::Escape($fileName)) {
        throw "Hosted artifact index did not list $fileName"
      }
    }

    Invoke-DownloadHostedArtifact -FileName $script:firstArtifacts.WorkstationMsiFileName -DestinationPath (Join-Path $downloadsRoot $script:firstArtifacts.WorkstationMsiFileName)
    Invoke-DownloadHostedArtifact -FileName $script:firstArtifacts.BundleFileName -DestinationPath (Join-Path $downloadsRoot $script:firstArtifacts.BundleFileName)
    "Hosted artifact library listed and served the expected initial rollout files."
  }))

  $results.Add((Invoke-And-Log -Name "07-install-client-from-downloaded-provisioned-msi" -Action {
    $downloadedMsi = Join-Path $downloadsRoot $script:firstArtifacts.WorkstationMsiFileName
    Install-MsiQuiet -MsiPath $downloadedMsi -LogPath (Join-Path $logsRoot "07-install-provisioned-msi.log")
    Assert-ClientConfig -ExpectedServerIp $script:expectedClientFacingServerIp -ExpectedServerPort "8001" -ExpectedPopupTheme "Modern" -ExpectedPopupPosition "Center" -ExpectedNotificationSound "Chime" -ExpectedRunOnStartup:$false -ExpectedPinToTray:$true -ExpectedPlayAlertSound:$false -ExpectedPlayResponseSound:$false
    "Installed provisioned workstation MSI from $downloadedMsi"
  }))

  $results.Add((Invoke-And-Log -Name "08-launch-client-and-verify-initial-managed-rollout" -Action {
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
    $installedExe = Get-InstalledClientExePath
    $script:installedClientProcess = Start-InstalledClient -ExePath $installedExe -Suffix "operator-rollout-initial"
    Wait-ForFilePattern -Path $clientLogPath -Pattern "Applied signed server policy v1 from operator-rollout-server \(server\)\." -TimeoutSeconds 25 | Out-Null
    $policyState = Invoke-VerifyPolicyState -MinimumPolicyVersion 1
    $script:initialPolicyFingerprint = [string]$policyState.LastPolicyFingerprint
    if ([string]::IsNullOrWhiteSpace($script:initialPolicyFingerprint)) {
      throw "Initial policy fingerprint was empty."
    }
    Invoke-VerifyServerRuntimeClient -ClientName "Operator Rollout Client" -ExpectedPolicyFingerprint $script:initialPolicyFingerprint -MinimumPolicyVersion 1
    $policyState | Format-List
  }))

  $results.Add((Invoke-And-Log -Name "09-operational-alert-flow-after-initial-rollout" -Action {
    $script:legacyClient = New-WireClient -RegistrationLine "Legacy Rollout Sender|version=0.9.0.0|platform=Windows"
    Send-WireMessage -Client $legacyClient -Command "Alert" -Body "Initial rollout operational alert" | Out-Null
    Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null
    "Managed client received an operational alert after provisioned-MSI rollout."
  }))

  $results.Add((Invoke-And-Log -Name "10-change-policy-rebuild-artifacts-and-refresh-client" -Action {
    Stop-ProcessQuietly $script:installedClientProcess
    $script:installedClientProcess = $null
    Stop-IsolatedServerHarness
    Invoke-PolicyProfileSave -PopupTheme "Quiet" -PopupPosition "BottomRight" -AllowSound:$true -NotificationSound "Pulse" -PlayAlertSound:$true -PlayResponseSound:$false -RunOnStartup:$true -PinToTray:$false -EscalationEnabled:$false -EscalationDelaySeconds 0
    if (-not $UseCloudClaim) {
      Seed-IsolatedServerLicense
    }
    if ($FetchInstallersFromCloud) {
      Invoke-FetchInstallerFromCloud -ServerInstaller:$false | Out-Null
      if ($FetchServerInstallerFromCloud) {
        Invoke-FetchInstallerFromCloud -ServerInstaller:$true | Out-Null
      }
    }
    $script:expectedClientFacingServerIp = Get-ExpectedClientFacingServerIp
    $script:secondArtifacts = Invoke-ExportRolloutArtifacts -Label "updated"
    if ($FetchServerInstallerFromCloud) {
      $script:updatedServerUpdateKit = Invoke-ExportServerUpdateKit -Label "updated"
    }
    $script:serverHarness = Start-IsolatedServerHarness
    $installedExe = Get-InstalledClientExePath
    $script:installedClientProcess = Start-InstalledClient -ExePath $installedExe -Suffix "operator-rollout-updated"
    Invoke-QueuePolicyResend -ClientName "Operator Rollout Client"
    Wait-ForCondition -Description "client policy fingerprint refresh" -TimeoutSeconds 25 -Condition {
      if (-not (Test-Path $clientPolicyStatePath)) { return $false }
      try {
        $state = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
        return [bool]$state.LastSignatureValid -and
          -not [string]::IsNullOrWhiteSpace([string]$state.LastPolicyFingerprint) -and
          [string]$state.LastPolicyFingerprint -ne $script:initialPolicyFingerprint
      }
      catch {
        return $false
      }
    }
    $updatedPolicyState = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
    $script:updatedPolicyFingerprint = [string]$updatedPolicyState.LastPolicyFingerprint
    if ([string]::IsNullOrWhiteSpace($script:updatedPolicyFingerprint)) {
      throw "Updated policy fingerprint was empty."
    }
    Invoke-VerifyServerRuntimeClient -ClientName "Operator Rollout Client" -ExpectedPolicyFingerprint $script:updatedPolicyFingerprint -MinimumPolicyVersion 1
    "Managed client refreshed to the updated server policy."
  }))

  $results.Add((Invoke-And-Log -Name "11-operational-alert-flow-after-policy-change" -Action {
    if ($script:legacyClient) {
      Close-WireClient -Client $script:legacyClient
      $script:legacyClient = $null
    }
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
    $script:legacyClient = New-WireClient -RegistrationLine "Legacy Rollout Sender 2|version=0.9.0.0|platform=Windows"
    Send-WireMessage -Client $legacyClient -Command "Alert" -Body "Updated policy operational alert" | Out-Null
    Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null
    "Managed client still handled an operational alert after the central policy change."
  }))

  $results.Add((Invoke-And-Log -Name "12-traditional-rollout-via-pending-bundle" -Action {
    Stop-ProcessQuietly $script:installedClientProcess
    $script:installedClientProcess = $null
    if ($script:legacyClient) {
      Close-WireClient -Client $script:legacyClient
      $script:legacyClient = $null
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File $clientCleanupScript -IncludeInstallerCache | Out-Null
    Remove-ClientPolicyResidue

    $traditionalBaseMsi = if ($FetchInstallersFromCloud) { Get-CachedInstallerPath -ServerInstaller:$false } else { $ClientMsiPath }
    if ([string]::IsNullOrWhiteSpace($traditionalBaseMsi) -or -not (Test-Path $traditionalBaseMsi)) {
      throw "Traditional rollout could not find a usable base client MSI."
    }

    Install-MsiQuiet -MsiPath $traditionalBaseMsi -LogPath (Join-Path $logsRoot "12-install-base-client.log") -AdditionalProperties @('CNAME="Operator Rollout Client"')
    New-Item -ItemType Directory -Force -Path $clientPendingRoot | Out-Null
    $downloadedBundle = Join-Path $downloadsRoot $script:secondArtifacts.BundleFileName
    if (-not (Test-Path $downloadedBundle)) {
      Invoke-DownloadHostedArtifact -FileName $script:secondArtifacts.BundleFileName -DestinationPath $downloadedBundle
    }
    Copy-Item -LiteralPath $downloadedBundle -Destination (Join-Path $clientPendingRoot "DuressClientProvisioningBundle.zip") -Force

    $installedExe = Get-InstalledClientExePath
    $script:installedClientProcess = Start-InstalledClient -ExePath $installedExe -Suffix "operator-rollout-traditional"
    Wait-ForCondition -Description "traditional bundle apply and signed policy" -TimeoutSeconds 25 -Condition {
      if (-not (Test-Path $clientPolicyStatePath)) { return $false }
      try {
        $state = Get-Content $clientPolicyStatePath -Raw | ConvertFrom-Json
        return [bool]$state.LastSignatureValid -and
          [string]$state.LastPolicyFingerprint -eq $script:updatedPolicyFingerprint
      }
      catch {
        return $false
      }
    }
    Assert-ClientConfig -ExpectedServerIp $script:expectedClientFacingServerIp -ExpectedServerPort "8001" -ExpectedPopupTheme "Quiet" -ExpectedPopupPosition "BottomRight" -ExpectedNotificationSound "Pulse" -ExpectedRunOnStartup:$true -ExpectedPinToTray:$false -ExpectedPlayAlertSound:$true -ExpectedPlayResponseSound:$false
    Invoke-VerifyServerRuntimeClient -ClientName "Operator Rollout Client" -ExpectedPolicyFingerprint $script:updatedPolicyFingerprint -MinimumPolicyVersion 1
    "Traditional base-MSI plus Pending bundle rollout adopted the current server policy successfully."
  }))

  $results.Add((Invoke-And-Log -Name "13-operational-alert-flow-after-traditional-rollout" -Action {
    Remove-Item -LiteralPath $clientLogPath -Force -ErrorAction SilentlyContinue
    $script:legacyClient = New-WireClient -RegistrationLine "Legacy Rollout Sender 3|version=0.9.0.0|platform=Windows"
    Send-WireMessage -Client $legacyClient -Command "Alert" -Body "Traditional rollout operational alert" | Out-Null
    Wait-ForFilePattern -Path $clientLogPath -Pattern "Alert Received" -TimeoutSeconds 20 | Out-Null
    "Managed client received an operational alert after the traditional Pending-bundle rollout."
  }))

  $results.Add((Invoke-And-Log -Name "14-capture-deployment-and-operations-screenshots" -Action {
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-deployment-updated.png") -ServerDataRoot $serverDataRoot -StartupPage Deployment
    powershell -NoProfile -ExecutionPolicy Bypass -File $captureServerShotScript -OutputPath (Join-Path $shotsRoot "server-operations-updated.png") -ServerDataRoot $serverDataRoot -StartupPage Monitor
  }))

  $lines = @()
  $lines += "# Operator Rollout Regression Suite"
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
  if ($UseCloudClaim) {
    $lines += "- The isolated server completed the linked-cloud claim flow before rollout packaging."
  }
  if ($FetchInstallersFromCloud) {
    $lines += "- The server fetched the latest approved client MSI from Duress Cloud before packaging, instead of relying on a pre-supplied local MSI."
  }
  if ($FetchServerInstallerFromCloud) {
    $lines += "- The server also fetched the latest approved server MSI and generated a server update kit from the current licensed configuration."
  }
  $lines += "- Server policy was configured to an initial profile and used to generate raw bundles, workstation packages, terminal packages, workstation MSIs, and terminal MSIs."
  $lines += "- The hosted artifact library exposed those generated files over HTTP from the isolated server."
  $lines += "- Preferred rollout path: a downloaded provisioned workstation MSI was installed and verified."
  $lines += "- Operational behaviour was checked after rollout by sending real alert traffic to the managed client."
  $lines += "- The server policy was changed, artifacts were rebuilt, and the already-installed managed client refreshed to the new configuration."
  $lines += "- Traditional rollout path: a base MSI plus Pending provisioning bundle was exercised against the updated configuration."
  $lines += ""
  $lines += "## Key artifact files"
  $lines += ""
  if ($script:firstArtifacts) {
    $lines += "- Initial bundle: $($script:firstArtifacts.BundleFileName)"
    $lines += "- Initial workstation MSI: $($script:firstArtifacts.WorkstationMsiFileName)"
    $lines += "- Initial terminal MSI: $($script:firstArtifacts.TerminalMsiFileName)"
  }
  if (-not [string]::IsNullOrWhiteSpace($script:initialServerUpdateKit)) {
    $lines += "- Initial server update kit: $script:initialServerUpdateKit"
  }
  if ($script:secondArtifacts) {
    $lines += "- Updated bundle: $($script:secondArtifacts.BundleFileName)"
    $lines += "- Updated workstation MSI: $($script:secondArtifacts.WorkstationMsiFileName)"
    $lines += "- Updated terminal MSI: $($script:secondArtifacts.TerminalMsiFileName)"
  }
  if (-not [string]::IsNullOrWhiteSpace($script:updatedServerUpdateKit)) {
    $lines += "- Updated server update kit: $script:updatedServerUpdateKit"
  }
  $lines += ""
  $lines += "## Screenshots"
  $lines += ""
  foreach ($shot in (Get-ChildItem -Path $shotsRoot -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $lines += "- [$($shot.Name)]($($shot.FullName -replace '\\','/'))"
  }

  Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

  $failed = @($results | Where-Object { -not $_.Success })
  if ($failed.Count -gt 0) {
    throw ("Operator rollout regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
  }
}
finally {
  if ($legacyClient) {
    Close-WireClient -Client $legacyClient
  }
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

Write-Host "Operator rollout regression suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
