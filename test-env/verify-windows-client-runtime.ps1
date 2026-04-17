param(
    [string]$ClientExe = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_workspace-root.ps1")

if ([string]::IsNullOrWhiteSpace($ClientExe)) {
    $ClientExe = Join-Path (Get-DuressWorkspaceRoot -ScriptRoot $PSScriptRoot) "Duress2025\Duress\bin\Release\Duress.exe"
}

$signature = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32Probe
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOPMOST = 0x00000008;

    public static IntPtr[] GetWindowsForProcess(int processId)
    {
        var result = new List<IntPtr>();
        EnumWindows((hWnd, lParam) =>
        {
            uint candidateProcessId;
            GetWindowThreadProcessId(hWnd, out candidateProcessId);
            if (candidateProcessId == processId)
            {
                result.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);

        return result.ToArray();
    }
}
"@

Add-Type -TypeDefinition $signature | Out-Null

function New-ConfigRoot {
    param([string]$Name)

    $root = Join-Path (Join-Path $PSScriptRoot "sandbox") $Name
    if (Test-Path $root) {
        Remove-Item -Recurse -Force $root
    }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Write-ClientConfig {
    param(
        [string]$Root,
        [bool]$PinToTray
    )

    $general = @{
        CName    = "RuntimeProbe"
        Alert    = "Alert!"
        OK       = "OK!"
        ROS      = $false
        Pin      = $PinToTray
        Terminal = $false
    } | ConvertTo-Json

    $server = @{
        SIP   = "127.0.0.1"
        SPort = "6553"
    } | ConvertTo-Json

    $hotkey = @{
        MC         = "None"
        KC         = "None"
        lastHandle = ""
    } | ConvertTo-Json

    $webhooks = @{
        SlackUrl                  = ""
        TeamsUrl                  = ""
        GChatUrl                  = ""
        UseSlack                  = $false
        UseTeams                  = $false
        UseGChat                  = $false
        Mode                      = "AlertsOnly"
        EscalationEnabled         = $false
        EscalationDelaySeconds    = 0
        EscalationMessageTemplate = "Escalation: {ClientName} alert from {Sender} - {Message} at {Timestamp}"
    } | ConvertTo-Json

    Set-Content -Path (Join-Path $Root "gSettings.json") -Value $general
    Set-Content -Path (Join-Path $Root "settings.json") -Value $server
    Set-Content -Path (Join-Path $Root "hSettings.json") -Value $hotkey
    Set-Content -Path (Join-Path $Root "webhooks.json") -Value $webhooks
    Set-Content -Path (Join-Path $Root "slack.txt") -Value ""
}

function Start-IsolatedClient {
    param(
        [string]$Root,
        [string]$Suffix
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ClientExe
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = Split-Path $ClientExe
    $psi.Environment["DURESS_USER_DATA_ROOT"] = $Root
    $psi.Environment["DURESS_COMMON_DATA_ROOT"] = $Root
    $psi.Environment["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
    $psi.Environment["DURESS_MUTEX_NAME_SUFFIX"] = $Suffix
    return [System.Diagnostics.Process]::Start($psi)
}

function Stop-Client {
    param([System.Diagnostics.Process]$Process)

    if ($null -ne $Process -and -not $Process.HasExited) {
        $Process.Kill()
        $Process.WaitForExit(5000) | Out-Null
    }
}

function Get-WindowProbe {
    param([System.Diagnostics.Process]$Process)

    $candidateWindows = @()
    for ($i = 0; $i -lt 50; $i++) {
        $Process.Refresh()
        $handles = [Win32Probe]::GetWindowsForProcess($Process.Id)
        if ($handles.Length -gt 0) {
            $candidateWindows = foreach ($candidate in $handles) {
                $exStyle = [Win32Probe]::GetWindowLong($candidate, [Win32Probe]::GWL_EXSTYLE)
                [pscustomobject]@{
                    Handle  = $candidate
                    Visible = [Win32Probe]::IsWindowVisible($candidate)
                    TopMost = (($exStyle -band [Win32Probe]::WS_EX_TOPMOST) -ne 0)
                }
            }

            $preferred = $candidateWindows | Where-Object { $_.Visible } | Select-Object -First 1
            if (-not $preferred) {
                $preferred = $candidateWindows | Select-Object -First 1
            }

            if ($preferred) {
                return [pscustomobject]@{
                    HasWindow = $true
                    Visible   = $preferred.Visible
                    TopMost   = $preferred.TopMost
                }
            }
        }
        Start-Sleep -Milliseconds 200
    }

    return [pscustomobject]@{
        HasWindow = $false
        Visible   = $false
        TopMost   = $false
    }
}

$visibleRoot = New-ConfigRoot -Name "client-runtime-visible"
Write-ClientConfig -Root $visibleRoot -PinToTray:$false
$visibleProcess = Start-IsolatedClient -Root $visibleRoot -Suffix "visible_probe"
Start-Sleep -Seconds 3
$visibleProbe = Get-WindowProbe -Process $visibleProcess

if (-not $visibleProbe.HasWindow -or -not $visibleProbe.Visible -or -not $visibleProbe.TopMost) {
    Stop-Client -Process $visibleProcess
    throw "Visible-mode runtime probe failed. Result: $($visibleProbe | ConvertTo-Json -Compress)"
}

Stop-Client -Process $visibleProcess

$trayRoot = New-ConfigRoot -Name "client-runtime-tray"
Write-ClientConfig -Root $trayRoot -PinToTray:$true
$trayProcess = Start-IsolatedClient -Root $trayRoot -Suffix "tray_probe"
Start-Sleep -Seconds 3
$trayProbe = Get-WindowProbe -Process $trayProcess

if ($trayProbe.Visible) {
    Stop-Client -Process $trayProcess
    throw "Tray-mode runtime probe failed. Window should not be visible. Result: $($trayProbe | ConvertTo-Json -Compress)"
}

Stop-Client -Process $trayProcess

Remove-Item -Recurse -Force $visibleRoot, $trayRoot -ErrorAction SilentlyContinue

Write-Host "Windows client runtime probe passed."
