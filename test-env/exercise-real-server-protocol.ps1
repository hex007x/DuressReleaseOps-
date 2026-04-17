param(
  [int]$ReceiveTimeoutMs = 20000,
  [int]$StartupDelayMs = 750
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DuressClient {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$ServerHost = "127.0.0.1",
    [int]$Port = 8001
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  $client.Connect($ServerHost, $Port)
  $stream = $client.GetStream()
  $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII, 1024, $true)
  $writer.NewLine = "`n"
  $writer.AutoFlush = $true
  $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

  $writer.WriteLine($Name)

  [pscustomobject]@{
    Name = $Name
    Client = $client
    Stream = $stream
    Writer = $writer
    Reader = $reader
  }
}

function Send-DuressMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $payload = "{0}%{1}`${2}" -f $Client.Name, $Command, $Message
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
  $Client.Stream.Write($bytes, 0, $bytes.Length)
  $Client.Stream.Flush()
  return $payload
}

function Receive-DuressMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [int]$TimeoutMs = 20000
  )

  $clientSocket = $Client.Client.Client
  if (-not $clientSocket.Poll($TimeoutMs * 1000, [System.Net.Sockets.SelectMode]::SelectRead)) {
    throw "Timed out waiting for message for $($Client.Name)."
  }

  $buffer = New-Object byte[] 512
  $read = $Client.Stream.Read($buffer, 0, $buffer.Length)
  if ($read -le 0) {
    throw "Connection closed while waiting for message for $($Client.Name)."
  }

  return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
}

$service = Get-Service -Name "DuressAlertService" -ErrorAction SilentlyContinue
if (-not $service -or $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  throw "DuressAlertService must be running before exercising the real server protocol."
}

$clientA = $null
$clientB = $null

try {
  $clientA = New-DuressClient -Name "Protocol Test Client A"
  $clientB = New-DuressClient -Name "Protocol Test Client B"
  Start-Sleep -Milliseconds $StartupDelayMs

  $sentAlert = Send-DuressMessage -Client $clientA -Command "Alert" -Message "Protocol alert from A"
  $receivedByB = Receive-DuressMessage -Client $clientB -TimeoutMs $ReceiveTimeoutMs

  $sentResp = Send-DuressMessage -Client $clientB -Command " Resp" -Message "Protocol response from B"
  $receivedByA = Receive-DuressMessage -Client $clientA -TimeoutMs $ReceiveTimeoutMs

  $sentAck = Send-DuressMessage -Client $clientA -Command " Ackn" -Message "Protocol reset from A"
  $receivedAckByB = Receive-DuressMessage -Client $clientB -TimeoutMs $ReceiveTimeoutMs

  [pscustomobject]@{
    AlertSent = $sentAlert
    AlertReceivedByB = $receivedByB
    ResponseSent = $sentResp
    ResponseReceivedByA = $receivedByA
    AckSent = $sentAck
    AckReceivedByB = $receivedAckByB
  }
}
finally {
  foreach ($item in @($clientA, $clientB)) {
    if ($null -ne $item) {
      try { $item.Writer.Dispose() } catch {}
      try { $item.Reader.Dispose() } catch {}
      try { $item.Stream.Dispose() } catch {}
      try { $item.Client.Close() } catch {}
    }
  }
}
