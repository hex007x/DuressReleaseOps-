Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DuressSettingsFile {
  $programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
  return Join-Path $programDataRoot "Settings.xml"
}

function Protect-DuressSetting {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  if ($Value.StartsWith("enc:", [StringComparison]::Ordinal)) {
    return $Value
  }

  $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine)

  return "enc:" + [Convert]::ToBase64String($protectedBytes)
}

function Load-DuressSettingsXml {
  $settingsFile = Get-DuressSettingsFile
  if (-not (Test-Path $settingsFile)) {
    throw "Settings file not found: $settingsFile"
  }

  [xml]$doc = Get-Content $settingsFile
  $settingNode = $doc.SelectSingleNode("/Settings/Setting")
  if (-not $settingNode) {
    throw "Invalid settings file: missing /Settings/Setting"
  }

  return [pscustomobject]@{
    SettingsFile = $settingsFile
    Document = $doc
    SettingNode = $settingNode
  }
}

function Set-DuressSettingNode {
  param(
    [Parameter(Mandatory = $true)]$Context,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
  )

  $doc = $Context.Document
  $settingNode = $Context.SettingNode
  $node = $doc.SelectSingleNode("/Settings/Setting/$Name")
  if (-not $node) {
    $node = $doc.CreateElement($Name)
    [void]$settingNode.AppendChild($node)
  }

  $node.InnerText = $Value
}

function Save-DuressSettingsXml {
  param([Parameter(Mandatory = $true)]$Context)

  $Context.Document.Save($Context.SettingsFile)
}
