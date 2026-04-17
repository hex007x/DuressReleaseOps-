param(
  [ValidateRange(1, 10)][int]$RetryCount = 3,
  [ValidateRange(1, 300)][int]$BackoffSeconds = 2,
  [ValidateRange(1, 300)][int]$RequestTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_settings-common.ps1")

$context = Load-DuressSettingsXml
Set-DuressSettingNode -Context $context -Name "NotificationRetryCount" -Value $RetryCount.ToString()
Set-DuressSettingNode -Context $context -Name "NotificationRetryBackoffSeconds" -Value $BackoffSeconds.ToString()
Set-DuressSettingNode -Context $context -Name "NotificationRequestTimeoutSeconds" -Value $RequestTimeoutSeconds.ToString()
Save-DuressSettingsXml -Context $context

Write-Host "Updated notification policy:"
Write-Host "  Retry count     :" $RetryCount
Write-Host "  Backoff seconds :" $BackoffSeconds
Write-Host "  Timeout seconds :" $RequestTimeoutSeconds
