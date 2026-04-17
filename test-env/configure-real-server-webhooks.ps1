param(
  [string]$BaseUrl = "http://127.0.0.1:8065",
  [ValidateSet("AlertsOnly", "All")][string]$Mode = "AlertsOnly",
  [switch]$Disable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$settingsFile = Join-Path $programDataRoot "Settings.xml"

if (-not (Test-Path $settingsFile)) {
  throw "Settings file not found: $settingsFile"
}

[xml]$doc = Get-Content $settingsFile
$settingNode = $doc.SelectSingleNode("/Settings/Setting")

function Set-OrCreateNode {
  param([string]$Name, [string]$Value)
  $node = $doc.SelectSingleNode("/Settings/Setting/$Name")
  if (-not $node) {
    $node = $doc.CreateElement($Name)
    [void]$settingNode.AppendChild($node)
  }
  $node.InnerText = $Value
}

if ($Disable) {
  Set-OrCreateNode "UseSlack" "False"
  Set-OrCreateNode "SlackUrl" ""
  Set-OrCreateNode "UseTeams" "False"
  Set-OrCreateNode "TeamsUrl" ""
  Set-OrCreateNode "UseGoogleChat" "False"
  Set-OrCreateNode "GoogleChatUrl" ""
} else {
  Set-OrCreateNode "UseSlack" "True"
  Set-OrCreateNode "SlackUrl" "$BaseUrl/slack"
  Set-OrCreateNode "UseTeams" "True"
  Set-OrCreateNode "TeamsUrl" "$BaseUrl/teams"
  Set-OrCreateNode "UseGoogleChat" "True"
  Set-OrCreateNode "GoogleChatUrl" "$BaseUrl/google-chat"
}

Set-OrCreateNode "NotificationMode" $Mode
$doc.Save($settingsFile)

Write-Host "Updated real server webhook settings:"
if ($Disable) {
  Write-Host "  Mode: disabled"
} else {
  Write-Host "  Base URL:" $BaseUrl
  Write-Host "  Mode    :" $Mode
}
