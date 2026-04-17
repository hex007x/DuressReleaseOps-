Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $scriptRoot "build-real-server.ps1"
$serviceName = "DuressAlertService"
$serverBuildRoot = Join-Path $scriptRoot "server-build"
$serverExe = Join-Path $serverBuildRoot "DuressServer.exe"
$serverConfig = Join-Path $serverBuildRoot "DuressServer.exe.config"
$serverPdb = Join-Path $serverBuildRoot "DuressServer.pdb"

& $buildScript

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
  if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $serviceName
    $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20))
  }
}

Write-Host "Real server binaries are rebuilt in:" $serverBuildRoot
Write-Host "If the service was installed from this path, it is now ready to be started again."

if ($service) {
  Start-Service -Name $serviceName
  $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
  Write-Host "Real server service restarted."
}
