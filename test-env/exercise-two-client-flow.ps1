Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$clientALog = Join-Path $scriptRoot "sandbox\clients\client-a\user-data\DuressText.mdl"
$clientBLog = Join-Path $scriptRoot "sandbox\clients\client-b\user-data\DuressText.mdl"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DuressNative {
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
  $callback = [DuressNative+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    [uint32]$windowProcessId = 0
    [void][DuressNative]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)
    if ($windowProcessId -eq $ProcessId) {
      $class = New-Object System.Text.StringBuilder 256
      [void][DuressNative]::GetClassName($hWnd, $class, $class.Capacity)
      if ($class.ToString() -like "WindowsForms10.Window.8*") {
        $handles.Add($hWnd) | Out-Null
      }
    }
    return $true
  }

  [DuressNative]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
  if ($handles.Count -eq 0) {
    throw "Could not find a primary client window for PID $ProcessId."
  }

  return $handles[0]
}

function Click-Window {
  param([IntPtr]$Handle)

  [void][DuressNative]::SetForegroundWindow($Handle)
  Start-Sleep -Milliseconds 250
  $lParam = [IntPtr]((20 -bor (20 -shl 16)))
  [void][DuressNative]::PostMessage($Handle, 0x0201, [IntPtr]1, $lParam)
  [void][DuressNative]::PostMessage($Handle, 0x0202, [IntPtr]0, $lParam)
}

$clients = Get-Process Duress -ErrorAction Stop | Sort-Object StartTime
if ($clients.Count -lt 2) {
  throw "Need two running Duress processes before exercising the flow."
}

$clientAHandle = Get-PrimaryWindowHandle -ProcessId $clients[0].Id
$clientBHandle = Get-PrimaryWindowHandle -ProcessId $clients[1].Id

# A sends alert, B sends response, A sends reset/clear.
Click-Window -Handle $clientAHandle
Start-Sleep -Seconds 2
Click-Window -Handle $clientBHandle
Start-Sleep -Seconds 2
Click-Window -Handle $clientAHandle
Start-Sleep -Seconds 2

Write-Host "Client A log tail:"
Get-Content $clientALog -ErrorAction SilentlyContinue | Select-Object -Last 10
Write-Host ""
Write-Host "Client B log tail:"
Get-Content $clientBLog -ErrorAction SilentlyContinue | Select-Object -Last 10
