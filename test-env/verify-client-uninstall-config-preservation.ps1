param(
    [string]$ClientExe = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
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

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Backup-FolderIfPresent {
    param(
        [string]$SourcePath,
        [string]$BackupPath
    )

    if (Test-Path -LiteralPath $SourcePath) {
        Move-Item -LiteralPath $SourcePath -Destination $BackupPath
        return $true
    }

    return $false
}

function Restore-FolderIfBackedUp {
    param(
        [string]$BackupPath,
        [string]$TargetPath
    )

    if (Test-Path -LiteralPath $BackupPath) {
        Remove-FolderIfPresent -Path $TargetPath
        Move-Item -LiteralPath $BackupPath -Destination $TargetPath
    }
}

function Get-ConfigSnapshot {
    param([string]$Folder)

    if (-not (Test-Path -LiteralPath $Folder)) {
        throw "Expected folder missing: $Folder"
    }

    return Get-ChildItem -LiteralPath $Folder -File |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Length = $_.Length
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
}

function Assert-SnapshotsEqual {
    param(
        [object[]]$Before,
        [object[]]$After,
        [string]$Label
    )

    if ($Before.Count -ne $After.Count) {
        throw "$Label file count changed across uninstall."
    }

    for ($i = 0; $i -lt $Before.Count; $i++) {
        if ($Before[$i].Name -ne $After[$i].Name) {
            throw "$Label file set changed across uninstall."
        }

        if ($Before[$i].Length -ne $After[$i].Length -or $Before[$i].Hash -ne $After[$i].Hash) {
            throw "$Label file '$($Before[$i].Name)' changed across uninstall."
        }
    }
}

function Invoke-InstallUtil {
    param(
        [string[]]$Arguments,
        [string]$LogFile
    )

    $installUtil = Get-InstallUtilPath
    & $installUtil /LogFile=$LogFile @Arguments $ClientExe | Out-Null
}

function Stop-DuressIfRunning {
    Get-Process -Name "Duress" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

$sandboxRoot = Join-Path $PSScriptRoot "sandbox\uninstall-config-preservation"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $sandboxRoot ("backup-" + $timestamp)
$userFolder = Join-Path $env:APPDATA "Duress Alert"
$commonFolder = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) "Duress Alert"
$desktopInstallLog = Join-Path $sandboxRoot "desktop-install.log"
$desktopUninstallLog = Join-Path $sandboxRoot "desktop-uninstall.log"
$terminalInstallLog = Join-Path $sandboxRoot "terminal-install.log"
$terminalUninstallLog = Join-Path $sandboxRoot "terminal-uninstall.log"
$desktopUserBackup = Join-Path $backupRoot "user-original"
$desktopCommonBackup = Join-Path $backupRoot "common-original"

if (-not (Test-Path -LiteralPath $ClientExe)) {
    throw "Client executable not found: $ClientExe"
}

New-Item -ItemType Directory -Force -Path $sandboxRoot | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$userBackedUp = $false
$commonBackedUp = $false

try {
    Stop-DuressIfRunning

    $userBackedUp = Backup-FolderIfPresent -SourcePath $userFolder -BackupPath $desktopUserBackup
    $commonBackedUp = Backup-FolderIfPresent -SourcePath $commonFolder -BackupPath $desktopCommonBackup

    Remove-FolderIfPresent -Path $userFolder
    Remove-FolderIfPresent -Path $commonFolder

    Invoke-InstallUtil -LogFile $desktopInstallLog -Arguments @(
        "/CNAME=PreserveDesktop01",
        "/SIP=10.90.0.10",
        "/SPORT=8301",
        "/ALERTMSG=Desktop Preserve",
        "/OKMSG=Desktop OK",
        "/ROS=1",
        "/PIN=1",
        "/MOD=Control",
        "/HOTKEY=F12",
        "/USESLACK=1",
        "/SLACKURL=https://example.invalid/preserve-desktop",
        "/WEBHOOKMODE=All",
        "/ESCALATIONENABLED=1",
        "/ESCSECONDS=60",
        "/ESCTEMPLATE=Desktop preserve {ClientName}",
        "/TERMINAL=0"
    )

    $desktopBefore = Get-ConfigSnapshot -Folder $commonFolder

    Invoke-InstallUtil -LogFile $desktopUninstallLog -Arguments @("/u")

    $desktopAfter = Get-ConfigSnapshot -Folder $commonFolder
    Assert-SnapshotsEqual -Before $desktopBefore -After $desktopAfter -Label "Desktop/common config"

    Remove-FolderIfPresent -Path $userFolder
    Remove-FolderIfPresent -Path $commonFolder

    Invoke-InstallUtil -LogFile $terminalInstallLog -Arguments @(
        "/CNAME=PreserveTerminal01",
        "/SIP=10.90.0.20",
        "/SPORT=8302",
        "/ALERTMSG=Terminal Preserve",
        "/OKMSG=Terminal OK",
        "/ROS=0",
        "/PIN=1",
        "/MOD=Alt",
        "/HOTKEY=F11",
        "/USETEAMS=1",
        "/TEAMSURL=https://example.invalid/preserve-terminal",
        "/WEBHOOKMODE=AlertsOnly",
        "/ESCALATIONENABLED=0",
        "/ESCSECONDS=0",
        "/ESCTEMPLATE=Terminal preserve {ClientName}",
        "/TERMINAL=1"
    )

    $terminalBefore = Get-ConfigSnapshot -Folder $userFolder

    Invoke-InstallUtil -LogFile $terminalUninstallLog -Arguments @("/u")

    $terminalAfter = Get-ConfigSnapshot -Folder $userFolder
    Assert-SnapshotsEqual -Before $terminalBefore -After $terminalAfter -Label "Terminal/user config"

    Remove-FolderIfPresent -Path $userFolder
    Remove-FolderIfPresent -Path $commonFolder
}
finally {
    Restore-FolderIfBackedUp -BackupPath $desktopUserBackup -TargetPath $userFolder
    Restore-FolderIfBackedUp -BackupPath $desktopCommonBackup -TargetPath $commonFolder
}

Write-Host "Windows client uninstall/config-preservation verification passed."
