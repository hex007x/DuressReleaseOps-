param(
  [string]$PortalUrl = "http://127.0.0.1:8055/licenses/check-in",
  [string]$Token = "local-test-token",
  [int]$CheckHours = 24,
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
if (-not $settingNode) {
  throw "Could not find /Settings/Setting in $settingsFile"
}

function Set-OrCreateNode {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()]
    [Parameter(Mandatory = $true)][string]$Value
  )

  $node = $doc.SelectSingleNode("/Settings/Setting/$Name")
  if (-not $node) {
    $node = $doc.CreateElement($Name)
    [void]$settingNode.AppendChild($node)
  }
  $node.InnerText = $Value
}

if ($Disable) {
  Set-OrCreateNode -Name "LicensePortalUrl" -Value ""
  Set-OrCreateNode -Name "LicenseCheckEnabled" -Value "False"
  Set-OrCreateNode -Name "LicenseCheckHours" -Value "24"
  Set-OrCreateNode -Name "LicenseApiToken" -Value ""
} else {
  Set-OrCreateNode -Name "LicensePortalUrl" -Value $PortalUrl
  Set-OrCreateNode -Name "LicenseCheckEnabled" -Value "True"
  Set-OrCreateNode -Name "LicenseCheckHours" -Value $CheckHours.ToString()
  Set-OrCreateNode -Name "LicenseApiToken" -Value $Token
}

$doc.Save($settingsFile)

Write-Host "Updated real server license portal settings:"
Write-Host "  Settings :" $settingsFile
if ($Disable) {
  Write-Host "  Mode     : disabled"
} else {
  Write-Host "  URL      :" $PortalUrl
  Write-Host "  Token    :" $Token
  Write-Host "  Hours    :" $CheckHours
}
