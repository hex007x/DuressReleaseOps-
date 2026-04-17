param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\licensing-proof\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$licenseXmlPath = Join-Path $programDataRoot "License.v3.xml"
$licenseDatPath = Join-Path $programDataRoot "License.dat"
$runtimeStatusPath = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"
$serverLogPath = Join-Path $programDataRoot ("Logs\DuressAlert_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$screenshotsRoot = Join-Path $OutputRoot "screenshots"
$logsRoot = Join-Path $OutputRoot "logs"
$backupRoot = Join-Path $OutputRoot "backup"
$reportPath = Join-Path $OutputRoot "LICENSING_PROOF_REPORT.md"
$closeWindowsScript = Join-Path $scriptRoot "close-visible-test-windows.ps1"

New-Item -ItemType Directory -Force -Path $OutputRoot, $screenshotsRoot, $logsRoot, $backupRoot | Out-Null

function Backup-FileIfPresent {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath
  )

  if (Test-Path $SourcePath) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetPath) | Out-Null
    Copy-Item $SourcePath $TargetPath -Force
  }
}

function Restore-BackedUpFile {
  param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$TargetPath
  )

  if (Test-Path $BackupPath) {
    Copy-Item $BackupPath $TargetPath -Force
  }
  elseif (Test-Path $TargetPath) {
    Remove-Item $TargetPath -Force
  }
}

function Ensure-RealServiceInstalled {
  $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if (-not $service) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot "start-real-server.ps1") | Out-Null
    Start-Sleep -Seconds 4
    $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
    if (-not $service) {
      throw "DuressAlertService is not installed. start-real-server.ps1 could not provision it automatically."
    }
  }
}

function Start-RealServiceSafe {
  & (Join-Path $scriptRoot "stop-server.ps1") | Out-Null
  Start-Service -Name "DuressAlertService"
  Start-Sleep -Seconds 4
  $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if (-not $service) {
    throw "DuressAlertService is not installed."
  }
  return $service
}

function Stop-RealServiceSafe {
  $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
  if ($service -and $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name "DuressAlertService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
  }
}

function Get-LogTail {
  if (Test-Path $serverLogPath) {
    return (Get-Content $serverLogPath -Tail 20)
  }
  return @()
}

function Get-RuntimeStatusSummary {
  param(
    [int]$Attempts = 10,
    [int]$DelayMilliseconds = 500
  )

  for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
    if (Test-Path $runtimeStatusPath) {
      try {
        [xml]$runtime = Get-Content $runtimeStatusPath
        $currentClients = $runtime.SelectSingleNode('/LicenseRuntimeStatus/CurrentConnectedClients')
        $graceLimit = $runtime.SelectSingleNode('/LicenseRuntimeStatus/GraceClientLimit')
        $licenseState = $runtime.SelectSingleNode('/LicenseRuntimeStatus/LastCloudLicenseState')
        if ($currentClients -and $graceLimit -and $licenseState) {
          return "Clients=$($currentClients.InnerText); Grace=$($graceLimit.InnerText); State=$($licenseState.InnerText)"
        }
      }
      catch {
        if ($attempt -eq ($Attempts - 1)) {
          return "Runtime status unreadable: $($_.Exception.Message)"
        }
      }
    }

    Start-Sleep -Milliseconds $DelayMilliseconds
  }

  return "Runtime status unavailable."
}

function Invoke-ProtocolSmokeSafe {
  try {
    $result = & (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") -ReceiveTimeoutMs 15000 -StartupDelayMs 1000
    return [pscustomobject]@{
      Success = $true
      Detail = ($result | Out-String).Trim()
    }
  }
  catch {
    return [pscustomobject]@{
      Success = $false
      Detail = $_.Exception.Message
    }
  }
}

function Apply-LicenseScenario {
  param(
    [Parameter(Mandatory = $true)][string]$ScenarioName,
    [ValidateSet("Subscription", "Full", "Trial", "Demo")][string]$LicenseType = "Subscription",
    [int]$ValidDays = 30,
    [int]$MaxClients = 2,
    [switch]$NoLicense
  )

  Stop-RealServiceSafe

  if ($NoLicense) {
    Remove-Item $licenseXmlPath -Force -ErrorAction SilentlyContinue
    Remove-Item $licenseDatPath -Force -ErrorAction SilentlyContinue
  }
  else {
    & (Join-Path $scriptRoot "issue-test-license.ps1") -LicenseId $ScenarioName -LicenseType $LicenseType -MaxClients $MaxClients -ValidDays $ValidDays -OutputPath $licenseXmlPath | Out-Null
    Remove-Item $licenseDatPath -Force -ErrorAction SilentlyContinue
  }

  $serviceStatus = "Stopped"
  $protocol = $null
  $runtimeSummary = ""
  try {
    $service = Start-RealServiceSafe
    $serviceStatus = $service.Status.ToString()
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
      $protocol = Invoke-ProtocolSmokeSafe
    }
  }
  catch {
    $serviceStatus = "StartFailed: $($_.Exception.Message)"
  }

  $runtimeSummary = Get-RuntimeStatusSummary

  [pscustomobject]@{
    Scenario = $ScenarioName
    ServiceStatus = $serviceStatus
    ProtocolSucceeded = if ($protocol) { $protocol.Success } else { $false }
    ProtocolDetail = if ($protocol) { $protocol.Detail } else { "" }
    RuntimeSummary = $runtimeSummary
    LogTail = (Get-LogTail) -join " | "
  }
}

function Test-CapacityEnforcement {
  Stop-RealServiceSafe
  & (Join-Path $scriptRoot "issue-test-license.ps1") -LicenseId "LIC-CAPACITY-PROOF" -LicenseType Subscription -MaxClients 2 -ValidDays 30 -OutputPath $licenseXmlPath | Out-Null
  Remove-Item $licenseDatPath -Force -ErrorAction SilentlyContinue
  $before = if (Test-Path $serverLogPath) { @(Get-Content $serverLogPath) } else { @() }
  $service = Start-RealServiceSafe
  if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
    throw "Could not start service for capacity proof."
  }

  $clients = @()
  try {
    foreach ($name in @("Capacity A","Capacity B","Capacity C","Capacity D")) {
      $client = [System.Net.Sockets.TcpClient]::new()
      $client.Connect("127.0.0.1", 8001)
      $stream = $client.GetStream()
      $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII, 1024, $true)
      $writer.NewLine = "`n"
      $writer.AutoFlush = $true
      $writer.WriteLine($name)
      $clients += [pscustomobject]@{ Client = $client; Stream = $stream; Writer = $writer; Name = $name }
      Start-Sleep -Milliseconds 400
    }

    Start-Sleep -Seconds 2
    $after = if (Test-Path $serverLogPath) { @(Get-Content $serverLogPath) } else { @() }
    $newLines = if ($after.Count -gt $before.Count) { @($after[$before.Count..($after.Count - 1)]) } else { @() }
    $capacityLines = @($newLines | Where-Object {
      $_ -match "License usage warning" -or
      $_ -match "License usage grace" -or
      $_ -match "declined" -or
      $_ -match "capacity warning"
    })

    $runtimeSummary = ""
    if (Test-Path $runtimeStatusPath) {
      [xml]$runtime = Get-Content $runtimeStatusPath
      $runtimeSummary = "Clients=$($runtime.LicenseRuntimeStatus.CurrentConnectedClients); Grace=$($runtime.LicenseRuntimeStatus.GraceClientLimit)"
    }

    return [pscustomobject]@{
      Scenario = "Capacity enforcement"
      ServiceStatus = "Running"
      RuntimeSummary = $runtimeSummary
      CapacityLines = $capacityLines
    }
  }
  finally {
    foreach ($item in $clients) {
      try { $item.Writer.Dispose() } catch {}
      try { $item.Stream.Dispose() } catch {}
      try { $item.Client.Close() } catch {}
    }
  }
}

Ensure-RealServiceInstalled

Backup-FileIfPresent -SourcePath $licenseXmlPath -TargetPath (Join-Path $backupRoot "License.v3.xml")
Backup-FileIfPresent -SourcePath $licenseDatPath -TargetPath (Join-Path $backupRoot "License.dat")
Backup-FileIfPresent -SourcePath $runtimeStatusPath -TargetPath (Join-Path $backupRoot "LicenseRuntimeStatus.xml")

$scenarioResults = @()
$capacityResult = $null

try {
  $scenarioResults += Apply-LicenseScenario -ScenarioName "NO-LICENSE" -NoLicense
  $scenarioResults += Apply-LicenseScenario -ScenarioName "TRIAL-ACTIVE" -LicenseType Trial -ValidDays 7 -MaxClients 2
  $scenarioResults += Apply-LicenseScenario -ScenarioName "TRIAL-EXPIRED" -LicenseType Trial -ValidDays -1 -MaxClients 2
  $scenarioResults += Apply-LicenseScenario -ScenarioName "SUBSCRIPTION-ACTIVE" -LicenseType Subscription -ValidDays 30 -MaxClients 2
  $scenarioResults += Apply-LicenseScenario -ScenarioName "SUBSCRIPTION-EXPIRED" -LicenseType Subscription -ValidDays -1 -MaxClients 2
  $scenarioResults += Apply-LicenseScenario -ScenarioName "FULL-ACTIVE" -LicenseType Full -ValidDays 365 -MaxClients 2
  $capacityResult = Test-CapacityEnforcement

  & (Join-Path $scriptRoot "capture-monitor-screenshot.ps1") -OutputPath (Join-Path $screenshotsRoot "server-operations.png") -StartupPage Operations | Out-Null
  & (Join-Path $scriptRoot "capture-monitor-screenshot.ps1") -OutputPath (Join-Path $screenshotsRoot "server-configuration.png") -StartupPage Configuration | Out-Null
  & (Join-Path $scriptRoot "capture-monitor-screenshot.ps1") -OutputPath (Join-Path $screenshotsRoot "server-licensing.png") -StartupPage Licensing | Out-Null
  & (Join-Path $scriptRoot "capture-client-settings-screenshot.ps1") -OutputPath (Join-Path $screenshotsRoot "client-settings.png") | Out-Null
  & (Join-Path $scriptRoot "run-visual-demo.ps1") -OutputRoot $screenshotsRoot | Out-Null

  $lines = @()
  $lines += "# Licensing And Regression Proof"
  $lines += ""
  $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $lines += ""
  $lines += "## Scenario Results"
  $lines += ""
  foreach ($result in $scenarioResults) {
    $lines += "### $($result.Scenario)"
    $lines += ""
    $lines += "- Service status: $($result.ServiceStatus)"
    $lines += "- Protocol succeeded: $($result.ProtocolSucceeded)"
    if ($result.RuntimeSummary) { $lines += "- Runtime summary: $($result.RuntimeSummary)" }
    if ($result.ProtocolDetail) { $lines += "- Protocol detail: $($result.ProtocolDetail -replace '\r?\n',' ')" }
    if ($result.LogTail) { $lines += "- Log tail: $($result.LogTail)" }
    $lines += ""
  }

  if ($capacityResult) {
    $lines += "## Capacity Enforcement"
    $lines += ""
    $lines += "- Service status: $($capacityResult.ServiceStatus)"
    $lines += "- Runtime summary: $($capacityResult.RuntimeSummary)"
    foreach ($line in $capacityResult.CapacityLines) {
      $lines += "- $line"
    }
    $lines += ""
  }

  $lines += "## Screenshots"
  $lines += ""
  foreach ($shot in (Get-ChildItem -Path $screenshotsRoot -File | Sort-Object Name)) {
    $lines += "- [$($shot.Name)]($($shot.FullName))"
  }

  Set-Content -Path $reportPath -Value $lines -Encoding UTF8
  Write-Host "Licensing proof written to: $OutputRoot"
  Write-Host "Report: $reportPath"
}
finally {
  Stop-RealServiceSafe
  Restore-BackedUpFile -BackupPath (Join-Path $backupRoot "License.v3.xml") -TargetPath $licenseXmlPath
  Restore-BackedUpFile -BackupPath (Join-Path $backupRoot "License.dat") -TargetPath $licenseDatPath
  Restore-BackedUpFile -BackupPath (Join-Path $backupRoot "LicenseRuntimeStatus.xml") -TargetPath $runtimeStatusPath
  try {
    Start-RealServiceSafe | Out-Null
  }
  catch {
    Write-Warning "Could not restore the real service to running state automatically: $($_.Exception.Message)"
  }
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $closeWindowsScript | Out-Null
  }
  catch {}
}
