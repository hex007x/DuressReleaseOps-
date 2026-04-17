Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$backupRoot = Join-Path $scriptRoot "sandbox\real-server-backup"
$markerFile = Join-Path $runtimeRoot "real-server-backup.marker"

$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$settingsFile = Join-Path $programDataRoot "Settings.xml"
$licenseFile = Join-Path $programDataRoot "License.dat"
$signedLicenseFile = Join-Path $programDataRoot "License.v3.xml"
$logsDir = Join-Path $programDataRoot "Logs"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $backupRoot, $programDataRoot, $logsDir | Out-Null

function Backup-IfNeeded {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$BackupPath
  )

  if ((Test-Path $SourcePath) -and -not (Test-Path $BackupPath)) {
    Copy-Item $SourcePath $BackupPath -Force
  }
}

Backup-IfNeeded -SourcePath $settingsFile -BackupPath (Join-Path $backupRoot "Settings.xml")
Backup-IfNeeded -SourcePath $licenseFile -BackupPath (Join-Path $backupRoot "License.dat")
Backup-IfNeeded -SourcePath $signedLicenseFile -BackupPath (Join-Path $backupRoot "License.v3.xml")

if (-not (Test-Path $markerFile)) {
  Set-Content -Path $markerFile -Value "prepared"
}

$settingsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Settings>
  <Setting>
    <IP>127.0.0.1</IP>
    <Port>8001</Port>
    <EmailAddr></EmailAddr>
    <EmailPass></EmailPass>
    <EmailPort>587</EmailPort>
    <SSL>True</SSL>
    <SMTP>smtp.gmail.com</SMTP>
    <EmailProvider>SMTP</EmailProvider>
    <OAuthTenantId></OAuthTenantId>
    <OAuthClientId></OAuthClientId>
    <OAuthClientSecret></OAuthClientSecret>
    <OAuthRefreshToken></OAuthRefreshToken>
    <OAuthSenderUser></OAuthSenderUser>
    <MailAlerts>False</MailAlerts>
    <MailTo>user@domain.com</MailTo>
    <UseSlack>False</UseSlack>
    <SlackUrl></SlackUrl>
    <UseTeams>False</UseTeams>
    <TeamsUrl></TeamsUrl>
    <UseGoogleChat>False</UseGoogleChat>
    <GoogleChatUrl></GoogleChatUrl>
    <NotificationMode>AlertsOnly</NotificationMode>
    <NotificationRetryCount>3</NotificationRetryCount>
    <NotificationRetryBackoffSeconds>2</NotificationRetryBackoffSeconds>
    <NotificationRequestTimeoutSeconds>15</NotificationRequestTimeoutSeconds>
    <LicensePortalUrl></LicensePortalUrl>
    <LicenseCheckEnabled>True</LicenseCheckEnabled>
    <LicenseCheckHours>24</LicenseCheckHours>
    <LicenseApiToken></LicenseApiToken>
    <Version>3.0</Version>
  </Setting>
</Settings>
"@

Set-Content -Path $settingsFile -Value $settingsXml
Set-Content -Path $licenseFile -Value @(
  "FULL-LOCAL-TEST-12345"
  "Full"
  "9999-12-31"
)
& (Join-Path $scriptRoot "issue-test-license.ps1") -CustomerName "Local Test Customer" -LicenseId "LIC-LOCAL-REAL-SERVER" -LicenseType Subscription -MaxClients 2 -ValidDays 30 -OutputPath $signedLicenseFile

Write-Host "Prepared real server config:"
Write-Host "  ProgramData :" $programDataRoot
Write-Host "  Settings    :" $settingsFile
Write-Host "  License     :" $licenseFile
Write-Host "  Signed Lic. :" $signedLicenseFile
