param(
  [string]$OutputRoot = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "sandbox\demo-shots"),
  [switch]$OpenMonitorWindows,
  [switch]$KeepEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$shotsRoot = $OutputRoot
$closeWindowsScript = Join-Path $scriptRoot "close-visible-test-windows.ps1"

try {
  & (Join-Path $scriptRoot "reset-test-env.ps1")
  & (Join-Path $scriptRoot "start-test-env.ps1") -TwoClients
  if ($OpenMonitorWindows) {
    & (Join-Path $scriptRoot "monitor-test-env.ps1")
  }

  Start-Sleep -Seconds 3
  & (Join-Path $scriptRoot "capture-screenshot.ps1") -OutputPath (Join-Path $shotsRoot "01-connected.png")

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DuressNativeDemo {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
"@

function Get-PrimaryWindowHandle {
  param([int]$ProcessId)

  $handles = New-Object System.Collections.Generic.List[IntPtr]
  $callback = [DuressNativeDemo+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    [uint32]$windowProcessId = 0
    [void][DuressNativeDemo]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)
    if ($windowProcessId -eq $ProcessId) {
      $class = New-Object System.Text.StringBuilder 256
      [void][DuressNativeDemo]::GetClassName($hWnd, $class, $class.Capacity)
      if ($class.ToString() -like "WindowsForms10.Window.8*") {
        $handles.Add($hWnd) | Out-Null
      }
    }
    return $true
  }

  [DuressNativeDemo]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
  if ($handles.Count -eq 0) {
    throw "Could not find a primary client window for PID $ProcessId."
  }

  return $handles[0]
}

function Click-Window {
  param([IntPtr]$Handle)

  [void][DuressNativeDemo]::SetForegroundWindow($Handle)
  Start-Sleep -Milliseconds 250
  $lParam = [IntPtr]((20 -bor (20 -shl 16)))
  [void][DuressNativeDemo]::PostMessage($Handle, 0x0201, [IntPtr]1, $lParam)
  [void][DuressNativeDemo]::PostMessage($Handle, 0x0202, [IntPtr]0, $lParam)
}

  $clients = Get-Process Duress -ErrorAction Stop | Sort-Object StartTime
  if ($clients.Count -lt 2) {
    throw "Need two running Duress processes for the visual demo."
  }

  $clientAHandle = Get-PrimaryWindowHandle -ProcessId $clients[0].Id
  $clientBHandle = Get-PrimaryWindowHandle -ProcessId $clients[1].Id

  Click-Window -Handle $clientAHandle
  Start-Sleep -Seconds 2
  & (Join-Path $scriptRoot "capture-screenshot.ps1") -OutputPath (Join-Path $shotsRoot "02-alert.png")

  Click-Window -Handle $clientBHandle
  Start-Sleep -Seconds 2
  & (Join-Path $scriptRoot "capture-screenshot.ps1") -OutputPath (Join-Path $shotsRoot "03-response.png")

  Click-Window -Handle $clientAHandle
  Start-Sleep -Seconds 2
  & (Join-Path $scriptRoot "capture-screenshot.ps1") -OutputPath (Join-Path $shotsRoot "04-ack.png")

  Write-Host "Visual demo complete."
  Write-Host "Screenshots:"
  Get-ChildItem $shotsRoot | Select-Object FullName
}
finally {
  if (-not $KeepEnvironment) {
    & (Join-Path $scriptRoot "stop-server.ps1") | Out-Null
    Get-Process Duress -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }

  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $closeWindowsScript | Out-Null
  }
  catch {}
}
