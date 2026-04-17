Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sandboxRoot = Join-Path $scriptRoot "sandbox"
$commonRoot = Join-Path $sandboxRoot "common-data"
$runtimeRoot = Join-Path $sandboxRoot "runtime"
$clientsRoot = Join-Path $sandboxRoot "clients"

function Initialize-ClientSandbox {
  param(
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$ClientName,
    [Parameter(Mandatory = $true)][string]$Position
  )

  $clientRoot = Join-Path $clientsRoot $ClientId
  $userRoot = Join-Path $clientRoot "user-data"
  New-Item -ItemType Directory -Force -Path $userRoot | Out-Null

  $general = @{
    CName = $ClientName
    Alert = "$ClientName alert"
    OK = "$ClientName clear"
    ROS = $false
    Pin = $false
  } | ConvertTo-Json

  $server = @{
    SIP = "127.0.0.1"
    SPort = "8001"
  } | ConvertTo-Json

  $hotkey = @{
    MC = "None"
    KC = "None"
    lastHandle = ""
  } | ConvertTo-Json

  $webhooks = @{
    SlackUrl = ""
    TeamsUrl = ""
    GChatUrl = ""
    UseSlack = $false
    UseTeams = $false
    UseGChat = $false
    Mode = "AlertsOnly"
    EscalationEnabled = $false
    EscalationDelaySeconds = 0
    EscalationMessageTemplate = "Escalation: {ClientName} alert from {Sender} - {Message} at {Timestamp}"
  } | ConvertTo-Json

  Set-Content -Path (Join-Path $userRoot "gSettings.json") -Value $general
  Set-Content -Path (Join-Path $userRoot "settings.json") -Value $server
  Set-Content -Path (Join-Path $userRoot "hSettings.json") -Value $hotkey
  Set-Content -Path (Join-Path $userRoot "webhooks.json") -Value $webhooks
  Set-Content -Path (Join-Path $userRoot "slack.txt") -Value ""
  Set-Content -Path (Join-Path $userRoot "pos.data") -Value $Position
}

New-Item -ItemType Directory -Force -Path $commonRoot, $runtimeRoot, $clientsRoot | Out-Null

$general = @{
  CName = "Shared Test Client"
  Alert = "Shared sandbox alert"
  OK = "Shared sandbox clear"
  ROS = $false
  Pin = $false
} | ConvertTo-Json

$server = @{
  SIP = "127.0.0.1"
  SPort = "8001"
} | ConvertTo-Json

$hotkey = @{
  MC = "None"
  KC = "None"
  lastHandle = ""
} | ConvertTo-Json

$webhooks = @{
  SlackUrl = ""
  TeamsUrl = ""
  GChatUrl = ""
  UseSlack = $false
  UseTeams = $false
  UseGChat = $false
  Mode = "AlertsOnly"
  EscalationEnabled = $false
  EscalationDelaySeconds = 0
  EscalationMessageTemplate = "Escalation: {ClientName} alert from {Sender} - {Message} at {Timestamp}"
} | ConvertTo-Json

Set-Content -Path (Join-Path $commonRoot "gSettings.json") -Value $general
Set-Content -Path (Join-Path $commonRoot "settings.json") -Value $server
Set-Content -Path (Join-Path $commonRoot "hSettings.json") -Value $hotkey
Set-Content -Path (Join-Path $commonRoot "webhooks.json") -Value $webhooks
Set-Content -Path (Join-Path $commonRoot "slack.txt") -Value ""

Initialize-ClientSandbox -ClientId "client-a" -ClientName "Local Test Client A" -Position "120 120"
Initialize-ClientSandbox -ClientId "client-b" -ClientName "Local Test Client B" -Position "220 120"

Write-Host "Prepared sandbox:"
Write-Host "  Common data:" $commonRoot
Write-Host "  Client A   :" (Join-Path $clientsRoot "client-a\user-data")
Write-Host "  Client B   :" (Join-Path $clientsRoot "client-b\user-data")
