param(
    [string]$ClientExe = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_workspace-root.ps1")

if ([string]::IsNullOrWhiteSpace($ClientExe)) {
    $ClientExe = Join-Path (Get-DuressWorkspaceRoot -ScriptRoot $PSScriptRoot) "Duress2025\Duress\bin\Release\Duress.exe"
}

function Get-InstallUtilPath {
    $path = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe"
    if (-not (Test-Path $path)) {
        throw "InstallUtil.exe not found at $path"
    }

    return $path
}

function Remove-FolderIfPresent {
    param([string]$Path)

    if (Test-Path $Path) {
        cmd /c "rd /s /q `"$Path`"" | Out-Null
    }
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Expected file missing: $Path"
    }

    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Invoke-ClientInstallerHook {
    param(
        [string[]]$Arguments,
        [string]$LogFile
    )

    $installUtil = Get-InstallUtilPath
    & $installUtil /LogFile=$LogFile @Arguments $ClientExe | Out-Null
}

$userFolder = Join-Path $env:APPDATA "Duress Alert"
$commonFolder = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) "Duress Alert"

Remove-FolderIfPresent -Path $userFolder
Remove-FolderIfPresent -Path $commonFolder

$sandboxRoot = Join-Path $PSScriptRoot "sandbox"
New-Item -ItemType Directory -Force -Path $sandboxRoot | Out-Null
$desktopLog = Join-Path $sandboxRoot "verify-client-desktop.log"
$terminalLog = Join-Path $sandboxRoot "verify-client-terminal.log"

Invoke-ClientInstallerHook -LogFile $desktopLog -Arguments @(
    "/CNAME=DesktopStation01",
    "/SIP=10.77.1.25",
    "/SPORT=8101",
    "/ALERTMSG=Desktop Alert",
    "/OKMSG=Desktop OK",
    "/ROS=1",
    "/PIN=1",
    "/MOD=Control",
    "/HOTKEY=F10",
    "/USESLACK=1",
    "/SLACKURL=https://example.invalid/slack",
    "/WEBHOOKMODE=All",
    "/ESCALATIONENABLED=1",
    "/ESCSECONDS=75",
    "/ESCTEMPLATE=Escalation desktop {ClientName}",
    "/TERMINAL=0"
)

$desktopGeneral = Read-JsonFile -Path (Join-Path $commonFolder "gSettings.json")
$desktopServer = Read-JsonFile -Path (Join-Path $commonFolder "settings.json")
$desktopWebhooks = Read-JsonFile -Path (Join-Path $commonFolder "webhooks.json")

if ($desktopGeneral.CName -ne "DesktopStation01" -or $desktopGeneral.Terminal -ne $false) {
    throw "Desktop-mode general config validation failed."
}

if ($desktopServer.SIP -ne "10.77.1.25" -or $desktopServer.SPort -ne "8101") {
    throw "Desktop-mode server config validation failed."
}

if ($desktopWebhooks.Mode -ne "All" -or $desktopWebhooks.UseSlack -ne $true) {
    throw "Desktop-mode webhook config validation failed."
}

Remove-FolderIfPresent -Path $userFolder
Remove-FolderIfPresent -Path $commonFolder

Invoke-ClientInstallerHook -LogFile $terminalLog -Arguments @(
    "/CNAME=TerminalUser01",
    "/SIP=10.88.2.40",
    "/SPORT=8202",
    "/ALERTMSG=Terminal Alert",
    "/OKMSG=Terminal OK",
    "/ROS=0",
    "/PIN=1",
    "/MOD=Alt",
    "/HOTKEY=F11",
    "/USETEAMS=1",
    "/TEAMSURL=https://example.invalid/teams",
    "/WEBHOOKMODE=AlertsOnly",
    "/ESCALATIONENABLED=0",
    "/ESCSECONDS=0",
    "/ESCTEMPLATE=Escalation terminal {ClientName}",
    "/TERMINAL=1"
)

$terminalGeneral = Read-JsonFile -Path (Join-Path $userFolder "gSettings.json")
$terminalServer = Read-JsonFile -Path (Join-Path $userFolder "settings.json")
$terminalWebhooks = Read-JsonFile -Path (Join-Path $userFolder "webhooks.json")

if ($terminalGeneral.CName -ne "TerminalUser01" -or $terminalGeneral.Terminal -ne $true) {
    throw "Terminal-mode general config validation failed."
}

if ($terminalServer.SIP -ne "10.88.2.40" -or $terminalServer.SPort -ne "8202") {
    throw "Terminal-mode server config validation failed."
}

if ($terminalWebhooks.Mode -ne "AlertsOnly" -or $terminalWebhooks.UseSlack -ne $false -or $terminalWebhooks.UseTeams -ne $true) {
    throw "Terminal-mode webhook config validation failed."
}

Remove-FolderIfPresent -Path $userFolder
Remove-FolderIfPresent -Path $commonFolder

Write-Host "Windows client config-mode verification passed."
