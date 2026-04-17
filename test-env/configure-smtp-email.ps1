param(
  [Parameter(Mandatory = $true)][string]$EmailAddress,
  [Parameter(Mandatory = $true)][string]$Password,
  [Parameter(Mandatory = $true)][string]$MailTo,
  [string]$SmtpServer = "smtp.office365.com",
  [ValidateRange(1, 65535)][int]$Port = 587,
  [bool]$UseSsl = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_settings-common.ps1")

$context = Load-DuressSettingsXml
Set-DuressSettingNode -Context $context -Name "MailAlerts" -Value "True"
Set-DuressSettingNode -Context $context -Name "MailTo" -Value $MailTo.Trim()
Set-DuressSettingNode -Context $context -Name "EmailProvider" -Value "SMTP"
Set-DuressSettingNode -Context $context -Name "EmailAddr" -Value $EmailAddress.Trim()
Set-DuressSettingNode -Context $context -Name "EmailPass" -Value (Protect-DuressSetting $Password)
Set-DuressSettingNode -Context $context -Name "SMTP" -Value $SmtpServer.Trim()
Set-DuressSettingNode -Context $context -Name "EmailPort" -Value $Port.ToString()
Set-DuressSettingNode -Context $context -Name "SSL" -Value $UseSsl.ToString()
Set-DuressSettingNode -Context $context -Name "OAuthTenantId" -Value ""
Set-DuressSettingNode -Context $context -Name "OAuthClientId" -Value ""
Set-DuressSettingNode -Context $context -Name "OAuthClientSecret" -Value ""
Set-DuressSettingNode -Context $context -Name "OAuthRefreshToken" -Value ""
Set-DuressSettingNode -Context $context -Name "OAuthSenderUser" -Value ""
Save-DuressSettingsXml -Context $context

Write-Host "Configured SMTP email provider."
Write-Host "  Sender :" $EmailAddress
Write-Host "  Target :" $MailTo
Write-Host "  SMTP   :" $SmtpServer
