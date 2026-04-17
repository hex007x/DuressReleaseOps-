param(
  [string]$OutputPath = (Join-Path $PSScriptRoot "sandbox\demo-shots\client-settings.png"),
  [int]$StartupDelaySeconds = 3,
  [string]$ClientExePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_workspace-root.ps1")

if ([string]::IsNullOrWhiteSpace($ClientExePath)) {
  $ClientExePath = Join-Path (Get-DuressWorkspaceRoot -ScriptRoot $PSScriptRoot) "Duress2025\Duress\bin\Release\Duress.exe"
}

if (-not (Test-Path $ClientExePath)) {
  throw "Could not find client executable at $ClientExePath"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path $scriptRoot "sandbox\client-settings-shot"
$userRoot = Join-Path $root "user"
$commonRoot = Join-Path $root "common"

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $userRoot, $commonRoot | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeClientShot
{
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT
  {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

  [DllImport("user32.dll")]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
}
"@

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ClientExePath
$psi.WorkingDirectory = Split-Path -Parent $ClientExePath
$psi.UseShellExecute = $false
$psi.EnvironmentVariables["DURESS_USER_DATA_ROOT"] = $userRoot
$psi.EnvironmentVariables["DURESS_COMMON_DATA_ROOT"] = $commonRoot
$psi.EnvironmentVariables["DURESS_SKIP_STARTUP_REGISTRY"] = "1"
$psi.EnvironmentVariables["DURESS_MUTEX_NAME_SUFFIX"] = "client-settings-shot"

$process = [System.Diagnostics.Process]::Start($psi)

try {
  Start-Sleep -Seconds $StartupDelaySeconds

  $targetHandle = [IntPtr]::Zero
  for ($i = 0; $i -lt 20 -and $targetHandle -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()

    $callback = [NativeClientShot+EnumWindowsProc]{
      param([IntPtr]$hWnd, [IntPtr]$lParam)
      [uint32]$windowProcessId = 0
      [void][NativeClientShot]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)
      if ($windowProcessId -eq $process.Id) {
        $class = New-Object System.Text.StringBuilder 256
        [void][NativeClientShot]::GetClassName($hWnd, $class, $class.Capacity)
        $rectProbe = New-Object NativeClientShot+RECT
        if ([NativeClientShot]::GetWindowRect($hWnd, [ref]$rectProbe)) {
          $widthProbe = $rectProbe.Right - $rectProbe.Left
          $heightProbe = $rectProbe.Bottom - $rectProbe.Top
          if ($widthProbe -ge 500 -and $heightProbe -ge 400) {
            $script:targetHandle = $hWnd
            return $false
          }
        }
      }
      return $true
    }
    [NativeClientShot]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
  }

  if ($targetHandle -eq [IntPtr]::Zero) {
    throw "Could not find the Duress client settings window."
  }

  [NativeClientShot]::ShowWindow($targetHandle, 5) | Out-Null
  [NativeClientShot]::SetForegroundWindow($targetHandle) | Out-Null

  $rect = New-Object NativeClientShot+RECT
  if (-not [NativeClientShot]::GetWindowRect($targetHandle, [ref]$rect)) {
    throw "Could not read the Duress client window bounds."
  }

  Start-Sleep -Seconds 2

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) {
    throw "The Duress client window bounds are invalid."
  }

  $bitmap = New-Object System.Drawing.Bitmap $width, $height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen(
      (New-Object System.Drawing.Point $rect.Left, $rect.Top),
      [System.Drawing.Point]::Empty,
      (New-Object System.Drawing.Size $width, $height))

    $dir = Split-Path -Parent $OutputPath
    if ($dir) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }

  Write-Host "Saved screenshot:" $OutputPath
}
finally {
  try {
    if (-not $process.HasExited) {
      $process.CloseMainWindow() | Out-Null
      Start-Sleep -Seconds 1
    }
  } catch {}

  try {
    if (-not $process.HasExited) {
      $process.Kill()
    }
  } catch {}
}
