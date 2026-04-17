Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $scriptRoot "build-real-server.ps1"
$prepareScript = Join-Path $scriptRoot "prepare-real-server.ps1"
$runtimeRoot = Join-Path $scriptRoot "sandbox\runtime"
$serverExe = Join-Path $scriptRoot "server-build\DuressServer.exe"
$serviceName = "DuressAlertService"
$serviceModeFile = Join-Path $runtimeRoot "server-mode.txt"

& $prepareScript

if (-not (Test-Path $serverExe)) {
  & $buildScript
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
  & $serverExe /install
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

  if (-not $service) {
    $binPath = ('"{0}" /service' -f $serverExe)
    $createOutput = & sc.exe create $serviceName binPath= $binPath start= auto DisplayName= "Duress Alert Server" 2>&1
    $createExitCode = $LASTEXITCODE
    if ($createExitCode -eq 0) {
      & sc.exe description $serviceName "Duress Alert Server" | Out-Null
    } elseif (($createOutput | Out-String) -match "Access is denied") {
      throw "Real server service installation requires an elevated PowerShell session."
    }

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  }

  if (-not $service) {
    throw "Real server service installation failed."
  }
}

sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/120000/restart/300000 | Out-Null

Set-Content -Path $serviceModeFile -Value "real"
Write-Host "Real server service is installed."
Write-Host "Service name:" $serviceName
