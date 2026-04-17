param(
  [string]$OutputPath = (Join-Path $PSScriptRoot "sandbox\demo-shots\server-monitor.png"),
  [int]$StartupDelaySeconds = 3,
  [string]$ServerExePath = "",
  [string]$ServerDataRoot,
  [string]$StartupPage = "Monitor"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_workspace-root.ps1")

if ([string]::IsNullOrWhiteSpace($ServerExePath)) {
  $ServerExePath = Join-Path (Get-DuressWorkspaceRoot -ScriptRoot $PSScriptRoot) "_external\DuressServer2025\DuressServer2025\bin\Release\DuressServer.exe"
}

$serverUi = $ServerExePath
if (-not (Test-Path $serverUi)) {
  throw "Could not find server UI executable at $serverUi"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeWindowTools
{
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

}
"@
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $serverUi
$psi.UseShellExecute = $false
$psi.EnvironmentVariables["DURESS_START_PAGE"] = $StartupPage
if (-not [string]::IsNullOrWhiteSpace($ServerDataRoot)) {
  $psi.EnvironmentVariables["DURESS_SERVER_DATA_ROOT"] = $ServerDataRoot
}

$process = [System.Diagnostics.Process]::Start($psi)

try {
  Start-Sleep -Seconds $StartupDelaySeconds

  for ($i = 0; $i -lt 20 -and $process.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
  }

  if ($process.MainWindowHandle -eq 0) {
    throw "Could not find the Duress server UI window."
  }

  [NativeWindowTools]::ShowWindow($process.MainWindowHandle, 5) | Out-Null
  [NativeWindowTools]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  $rect = New-Object NativeWindowTools+RECT
  if (-not [NativeWindowTools]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
    throw "Could not read the Duress server window bounds."
  }
  Start-Sleep -Seconds 2

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) {
    throw "The Duress server window bounds are invalid."
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
