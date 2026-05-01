Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $scriptRoot "install-real-server.ps1"
$serviceName = "DuressAlertService"
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$logsDir = Join-Path $programDataRoot "Logs"
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"

function Get-ListeningPortOwner {
  param([Parameter(Mandatory = $true)][int]$Port)

  $connection = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $connection) {
    return $null
  }

  $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    Port = $Port
    ProcessId = $connection.OwningProcess
    ProcessName = if ($process) { $process.ProcessName } else { "" }
  }
}

function Wait-ForCondition {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Condition,
    [Parameter(Mandatory = $true)][string]$Description,
    [int]$TimeoutSeconds = 20
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }

    Start-Sleep -Milliseconds 400
  }

  throw "Timed out waiting for: $Description"
}

& $installScript

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
  throw "Real server service '$serviceName' is not installed."
}

if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
  Start-Service -Name $serviceName
  $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(15))
}

$serviceInstance = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
if (-not $serviceInstance -or $serviceInstance.ProcessId -le 0) {
  throw "Could not determine the running process id for '$serviceName'."
}

$servicePid = [int]$serviceInstance.ProcessId
Wait-ForCondition -Description "Duress real service listener ownership on 127.0.0.1:8001" -TimeoutSeconds 20 -Condition {
  $owner = Get-ListeningPortOwner -Port 8001
  return $owner -and $owner.ProcessId -eq $servicePid
}

Set-Content -Path (Join-Path $runtimeRoot "server-mode.txt") -Value "real"

Write-Host "Started real server service:"
Write-Host "  Service:" $serviceName
Write-Host "  PID    :" $servicePid
Write-Host "  Logs   :" $logsDir
