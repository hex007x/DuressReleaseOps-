param(
  [int[]]$Ports = @(8001, 8002),
  [string[]]$AllowedProcessNames = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ListeningPortOwner {
  param(
    [Parameter(Mandatory = $true)][int]$Port
  )

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

foreach ($port in $Ports) {
  $owner = Get-ListeningPortOwner -Port $port
  if (-not $owner) {
    Write-Host ("Port {0}: available" -f $port)
    continue
  }

  if ($AllowedProcessNames -contains $owner.ProcessName) {
    Write-Host ("Port {0}: already owned by allowed process {1} (PID {2})" -f $port, $owner.ProcessName, $owner.ProcessId)
    continue
  }

  throw ("Required suite port {0} is already owned by '{1}' (PID {2}). Stop the foreign listener before running the regression harness." -f $port, $owner.ProcessName, $owner.ProcessId)
}
