<#
.SYNOPSIS
Removes a Duress Alert Windows client test install from the local machine.

.DESCRIPTION
Stops the Duress client if it is running, attempts MSI uninstall using the
known product code, and then removes common residual install/config/shortcut
locations used by the current Windows client test installs.

By default this is intentionally thorough for test cleanup:
- removes install folders
- removes per-user and shared config roots
- removes provisioning state and staged bundle residue under the shared config root
- removes shortcuts
- removes Run startup entry
- removes common IT4GP registry roots
- removes test override data roots from `DURESS_USER_DATA_ROOT` and
  `DURESS_COMMON_DATA_ROOT` when those environment variables are set

Use -WhatIf first if you want to preview the removal.

.PARAMETER IncludeInstallerCache
Also removes extra installer-cache style folders under Public Documents and TEMP.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\cleanup-duress-client-test-install-v2.ps1

Removes the Duress client test install and common residual config data.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\cleanup-duress-client-test-install-v2.ps1 -IncludeInstallerCache

Performs the same cleanup and also removes extra cached installer folders.

.NOTES
Script version: 2026.04.23.2
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeInstallerCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoots = @(
    'C:\Program Files\Duress Alert\Client',
    'C:\Program Files (x86)\Duress Alert\Client',
    'C:\Program Files\IT4GP\Duress Alert',
    'C:\Program Files (x86)\IT4GP\Duress Alert'
)
$configRoots = @(
    (Join-Path $env:APPDATA 'Duress Alert'),
    (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)) 'Duress Alert')
)
$shortcutPaths = @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Duress Alert.lnk'),
    (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)) 'Duress Alert.lnk'),
    (Join-Path $env:Public 'Desktop\Duress Alert.lnk')
)
$registryKeys = @(
    'HKCU:\Software\IT4GP',
    'HKLM:\Software\IT4GP',
    'HKLM:\Software\WOW6432Node\IT4GP'
)
$overrideConfigRoots = @(
    [Environment]::GetEnvironmentVariable('DURESS_USER_DATA_ROOT', 'Process'),
    [Environment]::GetEnvironmentVariable('DURESS_USER_DATA_ROOT', 'User'),
    [Environment]::GetEnvironmentVariable('DURESS_USER_DATA_ROOT', 'Machine'),
    [Environment]::GetEnvironmentVariable('DURESS_COMMON_DATA_ROOT', 'Process'),
    [Environment]::GetEnvironmentVariable('DURESS_COMMON_DATA_ROOT', 'User'),
    [Environment]::GetEnvironmentVariable('DURESS_COMMON_DATA_ROOT', 'Machine')
) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique

function Remove-PathIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($LiteralPath, 'Remove path')) {
        Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-RegistryKeyIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($RegistryPath, 'Remove registry key')) {
        Remove-Item -LiteralPath $RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Duress Alert client cleanup'

$runningClient = Get-Process -Name 'Duress' -ErrorAction SilentlyContinue
if ($runningClient) {
    foreach ($process in $runningClient) {
        if ($PSCmdlet.ShouldProcess(('Duress PID ' + $process.Id), 'Stop process')) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

$installedProducts = Get-ItemProperty `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.PSObject.Properties.Name -contains 'DisplayName') -and @('Duress Alert', 'Duress Alert Client') -contains $_.DisplayName
    }

if ($installedProducts) {
    foreach ($installedProduct in $installedProducts) {
        $productCode = $installedProduct.PSChildName
        Write-Host ('Product code: ' + $productCode)

        if (-not $productCode) {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess(('Duress Alert MSI registration ' + $productCode), 'Uninstall via msiexec')) {
            continue
        }

        $arguments = @('/x', $productCode, '/qn', '/norestart')
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        Write-Host ('msiexec exit code for ' + $productCode + ': ' + $process.ExitCode)
    }
}
else {
    Write-Host 'Product code: not found'
    Write-Host 'MSI registration was not found. Continuing with residue cleanup only.'
}

foreach ($path in $installRoots + $configRoots + $shortcutPaths) {
    Remove-PathIfPresent -LiteralPath $path
}

foreach ($overrideConfigRoot in $overrideConfigRoots) {
    Remove-PathIfPresent -LiteralPath $overrideConfigRoot
}

if ($PSCmdlet.ShouldProcess('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\DuressAlert', 'Remove startup entry')) {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'DuressAlert' -ErrorAction SilentlyContinue
}

foreach ($registryKey in $registryKeys) {
    Remove-RegistryKeyIfPresent -RegistryPath $registryKey
}

if ($IncludeInstallerCache) {
    $cacheFolders = @(
        'C:\Users\Public\Documents\Duress Alert',
        (Join-Path $env:TEMP 'Duress Alert')
    )

    foreach ($cacheFolder in $cacheFolders) {
        Remove-PathIfPresent -LiteralPath $cacheFolder
    }
}

foreach ($target in 'Process', 'User', 'Machine') {
    foreach ($variableName in 'DURESS_USER_DATA_ROOT', 'DURESS_COMMON_DATA_ROOT') {
        if ($PSCmdlet.ShouldProcess(($variableName + ' (' + $target + ')'), 'Clear environment variable')) {
            [Environment]::SetEnvironmentVariable($variableName, $null, $target)
        }
    }
}

Write-Host 'Cleanup completed.'
