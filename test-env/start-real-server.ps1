Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $scriptRoot "install-real-server.ps1"
$serviceName = "DuressAlertService"
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$logsDir = Join-Path $programDataRoot "Logs"
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"

& $installScript

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
  throw "Real server service '$serviceName' is not installed."
}

if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  Start-Service -Name $serviceName
  $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(15))
}

Set-Content -Path (Join-Path $runtimeRoot "server-mode.txt") -Value "real"

Write-Host "Started real server service:"
Write-Host "  Service:" $serviceName
Write-Host "  Logs   :" $logsDir
