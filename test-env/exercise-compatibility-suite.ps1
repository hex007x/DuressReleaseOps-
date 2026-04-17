param(
  [int]$LegacyPort = 8011,
  [switch]$IncludeRealService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$prepareScript = Join-Path $scriptRoot "prepare-sandbox.ps1"
$buildClientScript = Join-Path $scriptRoot "build-client.ps1"
$startLegacyScript = Join-Path $scriptRoot "start-legacy-wire-server.ps1"
$stopLegacyScript = Join-Path $scriptRoot "stop-legacy-wire-server.ps1"
$clientLog = Join-Path $scriptRoot "sandbox\clients\client-a\user-data\DuressText.mdl"
$settingsFile = Join-Path $scriptRoot "sandbox\clients\client-a\user-data\settings.json"
$commonRoot = Join-Path $scriptRoot "sandbox\common-data"
$userRoot = Join-Path $scriptRoot "sandbox\clients\client-a\user-data"

function New-WireClient {
  param(
    [Parameter(Mandatory = $true)][string]$RegistrationLine,
    [string]$ServerHost = "127.0.0.1",
    [int]$Port = 8011
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  $client.Connect($ServerHost, $Port)
  $stream = $client.GetStream()
  $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII, 1024, $true)
  $writer.NewLine = "`n"
  $writer.AutoFlush = $true
  $writer.WriteLine($RegistrationLine)

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

function Receive-WireMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [int]$TimeoutMs = 15000
  )

  $socket = $Client.Client.Client
  if (-not $socket.Poll($TimeoutMs * 1000, [System.Net.Sockets.SelectMode]::SelectRead)) {
    throw "Timed out waiting for message for $($Client.RegistrationLine)."
  }

  $buffer = New-Object byte[] 512
  $read = $Client.Stream.Read($buffer, 0, $buffer.Length)
  if ($read -le 0) {
    throw "Connection closed while waiting for message for $($Client.RegistrationLine)."
  }

  return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
}

function Close-WireClient {
  param([Parameter(Mandatory = $true)]$Client)
  try { $Client.Writer.Dispose() } catch {}
  try { $Client.Stream.Dispose() } catch {}
  try { $Client.Client.Close() } catch {}
}

function Get-LatestClientExePath {
  $latestPointer = Join-Path $scriptRoot "build\latest-build.txt"
  $releasesRoot = Join-Path $scriptRoot "build\releases"

  if (Test-Path $latestPointer) {
    $latestBuild = (Get-Content $latestPointer | Select-Object -First 1).Trim()
    if ($latestBuild) {
      $candidate = Join-Path $releasesRoot $latestBuild
      $candidateExe = Join-Path $candidate "Duress.exe"
      if (Test-Path $candidateExe) {
        return $candidateExe
      }
    }
  }

  $latestDir = Get-ChildItem -Path $releasesRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if ($latestDir) {
    $candidateExe = Join-Path $latestDir.FullName "Duress.exe"
    if (Test-Path $candidateExe) {
      return $candidateExe
    }
  }

  return $null
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

& $prepareScript
& $buildClientScript
& $stopLegacyScript | Out-Null
& $startLegacyScript -Port $LegacyPort | Out-Null

$serviceProtocol = $null
$legacyRaw = $null
$newClientLegacy = $null
$clientProcess = $null
$clientA = $null
$clientB = $null
$compatSender = $null

try {
  if ($IncludeRealService) {
    $service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
      throw "DuressAlertService must be running when -IncludeRealService is used."
    }
    $serviceProtocol = & (Join-Path $scriptRoot "exercise-real-server-protocol.ps1") -ReceiveTimeoutMs 20000 -StartupDelayMs 1000
  }

  $clientA = New-WireClient -RegistrationLine "Compat Modern A|version=1.1.0.0|platform=Windows" -Port $LegacyPort
  $clientB = New-WireClient -RegistrationLine "Compat Modern B|version=1.1.0.1|platform=Windows" -Port $LegacyPort
  Start-Sleep -Milliseconds 500

  $legacySent = Send-WireMessage -Client $clientA -Command "Alert" -Body "Compatibility alert from A"
  $legacyReceived = Receive-WireMessage -Client $clientB -TimeoutMs 15000
  $legacyRaw = [pscustomobject]@{
    Sent = $legacySent
    Received = $legacyReceived
    RegistrationLeakDetected = ($legacyReceived -like "Compat Modern A|version=*")
  }

  Set-ClientServerPort -Path $settingsFile -Port $LegacyPort
  if (Test-Path $clientLog) {
    Remove-Item $clientLog -Force
  }

  $exePath = Get-LatestClientExePath
  if (-not $exePath) {
    throw "Could not find a built client executable."
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exePath
  $psi.WorkingDirectory = Split-Path -Parent $exePath
  $psi.UseShellExecute = $false
  $psi.EnvironmentVariables["DURESS_USER_DATA_ROOT"] = $userRoot
  $psi.EnvironmentVariables["DURESS_COMMON_DATA_ROOT"] = $commonRoot
  $psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
  $psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = "compat-client-a"

  $clientProcess = [System.Diagnostics.Process]::Start($psi)
  Start-Sleep -Seconds 3

  $compatSender = New-WireClient -RegistrationLine "Legacy Leak Sender|version=9.9.9.9|platform=Windows" -Port $LegacyPort
  $sendPayload = Send-WireMessage -Client $compatSender -Command "Alert" -Body "Legacy server compatibility warning exercise"
  Start-Sleep -Seconds 4

  $clientLogText = if (Test-Path $clientLog) { Get-Content $clientLog -Raw } else { "" }
  $newClientLegacy = [pscustomobject]@{
    TriggerPayload = $sendPayload
    WarningLogged = ($clientLogText -match "Compatibility Warning")
    AlertReceivedLogged = ($clientLogText -match "Alert Received")
  }

  [pscustomobject]@{
    Suite = "Compatibility"
    RealServiceLegacyProtocol = $serviceProtocol
    LegacyWireRelay = $legacyRaw
    NewClientAgainstLegacyRelay = $newClientLegacy
    Recommendation = "Use the legacy-wire relay to validate mixed old-server/new-client behavior before release."
  } | Format-List
}
finally {
  foreach ($item in @($clientA, $clientB, $compatSender)) {
    if ($null -ne $item) {
      Close-WireClient -Client $item
    }
  }

  if ($clientProcess) {
    try {
      if (-not $clientProcess.HasExited) {
        $clientProcess.Kill()
        $clientProcess.WaitForExit(3000) | Out-Null
      }
    } catch {}
  }

  & $stopLegacyScript | Out-Null
}
