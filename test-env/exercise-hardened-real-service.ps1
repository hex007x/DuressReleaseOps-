param(
    [string]$HardenedBuildRoot = 'C:\OLDD\Duress\test-env\sandbox\hardened-release\server',
    [string]$ServerBuildRoot = 'C:\OLDD\Duress\test-env\server-build',
    [string]$ServiceName = 'DuressAlertService',
    [int]$StartupTimeoutSeconds = 20,
    [int]$ReceiveTimeoutMs = 20000,
    [int]$StartupDelayMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$prepareScript = Join-Path $scriptRoot 'prepare-real-server.ps1'
$startScript = Join-Path $scriptRoot 'start-real-server.ps1'
$stopScript = Join-Path $scriptRoot 'stop-real-server.ps1'
$protocolScript = Join-Path $scriptRoot 'exercise-real-server-protocol.ps1'
$showStatusScript = Join-Path $scriptRoot 'show-status.ps1'

$hardenedExe = Join-Path $HardenedBuildRoot 'DuressServer.exe'
$hardenedConfig = Join-Path $HardenedBuildRoot 'DuressServer.exe.config'
$hardenedPdb = Join-Path $HardenedBuildRoot 'DuressServer.pdb'

$targetExe = Join-Path $ServerBuildRoot 'DuressServer.exe'
$targetConfig = Join-Path $ServerBuildRoot 'DuressServer.exe.config'
$targetPdb = Join-Path $ServerBuildRoot 'DuressServer.pdb'

if (-not (Test-Path $hardenedExe)) {
    throw "Hardened server executable was not found at '$hardenedExe'."
}

if (-not (Test-Path $hardenedConfig)) {
    throw "Hardened server config was not found at '$hardenedConfig'."
}

if (-not (Test-Path $targetExe)) {
    throw "Real server build executable was not found at '$targetExe'."
}

& $prepareScript

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    throw "Real server service '$ServiceName' is not installed."
}

$serviceInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $ServiceName)
if (-not $serviceInfo) {
    throw "Could not inspect Windows service '$ServiceName'."
}

if ($serviceInfo.PathName -notmatch [Regex]::Escape($ServerBuildRoot)) {
    throw "Service '$ServiceName' is not running from '$ServerBuildRoot'. Current path: $($serviceInfo.PathName)"
}

$wasRunning = $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
$backupRoot = Join-Path $scriptRoot 'sandbox\hardened-service-backup'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

Copy-Item -Path $targetExe -Destination (Join-Path $backupRoot 'DuressServer.exe') -Force
Copy-Item -Path $targetConfig -Destination (Join-Path $backupRoot 'DuressServer.exe.config') -Force
if (Test-Path $targetPdb) {
    Copy-Item -Path $targetPdb -Destination (Join-Path $backupRoot 'DuressServer.pdb') -Force
}

$protocolResult = $null
$statusSummary = $null

try {
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        & $stopScript
        $service.Refresh()
    }

    Copy-Item -Path $hardenedExe -Destination $targetExe -Force
    Copy-Item -Path $hardenedConfig -Destination $targetConfig -Force
    if (Test-Path $hardenedPdb) {
        Copy-Item -Path $hardenedPdb -Destination $targetPdb -Force
    }

    & $startScript

    $service.Refresh()
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($StartupTimeoutSeconds))
    }

    $protocolResult = & $protocolScript -ReceiveTimeoutMs $ReceiveTimeoutMs -StartupDelayMs $StartupDelayMs
    $statusSummary = & $showStatusScript | Out-String
}
finally {
    try {
        & $stopScript
    }
    catch {
        Write-Warning ("Failed to stop real server service during hardened rehearsal cleanup. " + $_.Exception.Message)
    }

    if (Test-Path (Join-Path $backupRoot 'DuressServer.exe')) {
        Copy-Item -Path (Join-Path $backupRoot 'DuressServer.exe') -Destination $targetExe -Force
    }
    if (Test-Path (Join-Path $backupRoot 'DuressServer.exe.config')) {
        Copy-Item -Path (Join-Path $backupRoot 'DuressServer.exe.config') -Destination $targetConfig -Force
    }
    if (Test-Path (Join-Path $backupRoot 'DuressServer.pdb')) {
        Copy-Item -Path (Join-Path $backupRoot 'DuressServer.pdb') -Destination $targetPdb -Force
    }

    if ($wasRunning) {
        try {
            & $startScript
        }
        catch {
            Write-Warning ("Failed to restart the original real server service after cleanup. " + $_.Exception.Message)
        }
    }
}

Write-Host 'Hardened real-service rehearsal'
Write-Host ('Hardened build root: ' + $HardenedBuildRoot)
Write-Host ('Service name: ' + $ServiceName)
Write-Host ('Original service running before rehearsal: ' + $wasRunning)
Write-Host ''
Write-Host 'Protocol smoke result:'
$protocolResult | Format-List | Out-Host
Write-Host ''
Write-Host 'Status snapshot:'
Write-Host $statusSummary.TrimEnd()
