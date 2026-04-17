param(
  [string]$Sender = "Remote Tester",
  [ValidateSet("Alert", " Resp", " Ackn")]
  [string]$Command = "Alert",
  [string]$Message = "Injected test alert",
  [string]$ServerHost = "127.0.0.1",
  [int]$Port = 8001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tcp = New-Object System.Net.Sockets.TcpClient
try {
  $tcp.Connect($ServerHost, $Port)
  $payload = "$Sender%$Command`$$Message"
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
  $stream = $tcp.GetStream()
  $stream.Write($bytes, 0, $bytes.Length)
  $stream.Flush()
  Write-Host "Injected:" $payload
} finally {
  $tcp.Close()
}
