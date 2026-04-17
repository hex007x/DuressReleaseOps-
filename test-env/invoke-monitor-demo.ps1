param(
  [int]$HoldSeconds = 90,
  [string]$ServerHost = "127.0.0.1",
  [int]$Port = 8001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DemoClient {
  param(
    [Parameter(Mandatory = $true)][string]$RegistrationLine
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
    Client = $client
    Stream = $stream
    Writer = $writer
  }
}

function Send-DemoMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][string]$SenderName,
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$Body
  )

  $payload = "{0}%{1}`${2}" -f $SenderName, $Command, $Body
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
  $Client.Stream.Write($bytes, 0, $bytes.Length)
  $Client.Stream.Flush()
  return $payload
}

function Close-DemoClient {
  param(
    [Parameter(Mandatory = $true)]$Client
  )

  try { $Client.Writer.Dispose() } catch {}
  try { $Client.Stream.Dispose() } catch {}
  try { $Client.Client.Close() } catch {}
}

$service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
if (-not $service -or $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  throw "DuressAlertService must be running before invoking the monitor demo."
}

$clients = @()

try {
  $modernLiveName = "Monitor Modern Client"
  $legacyLiveName = "Monitor Legacy Client"

  $clients += New-DemoClient -RegistrationLine "$modernLiveName|version=1.1.0.0|platform=Windows"
  Start-Sleep -Milliseconds 350
  $clients += New-DemoClient -RegistrationLine $legacyLiveName
  Start-Sleep -Milliseconds 350

  $offlineLegacy = New-DemoClient -RegistrationLine "Monitor Legacy Offline"
  Start-Sleep -Milliseconds 350
  Close-DemoClient -Client $offlineLegacy

  $offlineModern = New-DemoClient -RegistrationLine "Monitor Modern Offline|version=1.0.4.0|platform=Windows"
  Start-Sleep -Milliseconds 350
  Close-DemoClient -Client $offlineModern

  $modernLive = $clients[0]
  $legacyLive = $clients[1]

  Send-DemoMessage -Client $modernLive -SenderName $modernLiveName -Command "Alert" -Body "Monitor demo alert from modern client" | Out-Null
  Start-Sleep -Seconds 4
  Send-DemoMessage -Client $legacyLive -SenderName $legacyLiveName -Command " Resp" -Body "Monitor demo response from legacy client" | Out-Null

  Write-Host "Monitor demo is active."
  Write-Host "Connected clients : $modernLiveName, $legacyLiveName"
  Write-Host "Offline history   : Monitor Legacy Offline, Monitor Modern Offline"
  Write-Host "State             : $modernLiveName is Under Duress, $legacyLiveName is Responded"
  Write-Host "Hold seconds      : $HoldSeconds"

  Start-Sleep -Seconds $HoldSeconds
}
finally {
  foreach ($client in $clients) {
    Close-DemoClient -Client $client
  }
}
