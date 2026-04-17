param(
  [Parameter(Mandatory = $true)][string]$ClientId,
  [Parameter(Mandatory = $true)][string]$ClientSecret,
  [Parameter(Mandatory = $true)][string]$RefreshToken,
  [Parameter(Mandatory = $true)][string]$SenderUser,
  [Parameter(Mandatory = $true)][string]$MailTo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_settings-common.ps1")

$context = Load-DuressSettingsXml
Set-DuressSettingNode -Context $context -Name "MailAlerts" -Value "True"
Set-DuressSettingNode -Context $context -Name "MailTo" -Value $MailTo.Trim()
Set-DuressSettingNode -Context $context -Name "EmailProvider" -Value "GmailOAuth"
Set-DuressSettingNode -Context $context -Name "OAuthClientId" -Value $ClientId.Trim()
Set-DuressSettingNode -Context $context -Name "OAuthClientSecret" -Value (Protect-DuressSetting $ClientSecret)
Set-DuressSettingNode -Context $context -Name "OAuthRefreshToken" -Value (Protect-DuressSetting $RefreshToken)
Set-DuressSettingNode -Context $context -Name "OAuthSenderUser" -Value $SenderUser.Trim()
Set-DuressSettingNode -Context $context -Name "OAuthTenantId" -Value ""
Set-DuressSettingNode -Context $context -Name "EmailAddr" -Value ""
Set-DuressSettingNode -Context $context -Name "EmailPass" -Value ""
Set-DuressSettingNode -Context $context -Name "SMTP" -Value "smtp.gmail.com"
Set-DuressSettingNode -Context $context -Name "EmailPort" -Value "587"
Set-DuressSettingNode -Context $context -Name "SSL" -Value "True"
Save-DuressSettingsXml -Context $context

Write-Host "Configured Gmail OAuth email provider."
Write-Host "  Sender :" $SenderUser
Write-Host "  Target :" $MailTo
