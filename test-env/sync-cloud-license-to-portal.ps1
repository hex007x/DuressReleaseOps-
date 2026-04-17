param(
    [string]$CloudLicensePath = "C:\OLDD\Duress\DuressCloud\artifacts\License.v3.xml",
    [ValidateSet("current", "renewed")][string]$Target = "renewed"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portalRoot = Join-Path $scriptRoot "sandbox\runtime\license-portal"
$targetPath = Join-Path $portalRoot ($Target + "-license.xml")

if (-not (Test-Path $CloudLicensePath)) {
    throw "Cloud license file not found: $CloudLicensePath"
}

New-Item -ItemType Directory -Force -Path $portalRoot | Out-Null
Copy-Item -Path $CloudLicensePath -Destination $targetPath -Force

Write-Host "Synced cloud license to portal slot:" $targetPath
