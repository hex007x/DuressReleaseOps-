Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "DuressAlertService"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if (-not $service) {
  Write-Host "Real server service is not installed."
  exit 0
}

if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
  Write-Host "Real server service is already stopped."
  exit 0
}

Stop-Service -Name $serviceName
$service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(15))
Write-Host "Stopped real server service."
