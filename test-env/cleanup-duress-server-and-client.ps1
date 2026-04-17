<#
.SYNOPSIS
Removes both the Duress Alert Windows server test install and the Windows client test install.

.DESCRIPTION
This is the easiest combined cleanup entry point when you want to clear both
the local Duress server and local Duress client from a test machine.

What it does:
- runs the Windows client cleanup script
- runs the Windows server uninstall/cleanup script

By default the server uninstall script preserves or restores prior server config
where possible. If you want a true wipe of the current Duress server runtime
data as well, use -PurgeServerProgramData.

Recommended usage:
1. Close any open Duress client/server manager windows first.
2. Run this script in an elevated PowerShell session if the server service is installed.
3. Use -WhatIf first if you want a preview of the client-side removals.

.PARAMETER IncludeClientInstallerCache
Passes -IncludeInstallerCache to the client cleanup script.

.PARAMETER PurgeServerProgramData
After uninstalling the server service, also removes the current
`C:\ProgramData\DuressAlert` folder.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\cleanup-duress-server-and-client.ps1

Uninstalls the test server service, cleans the test client install, and leaves
server ProgramData in its normal preserved/restored state.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\test-env\cleanup-duress-server-and-client.ps1 -IncludeClientInstallerCache -PurgeServerProgramData

Performs the combined cleanup and also removes extra client cache folders plus
the server ProgramData folder for a fuller wipe.

.NOTES
Run from an elevated PowerShell session when the server service may be installed.
Script version: 2026.04.13.2

Supported switches:
- `-IncludeClientInstallerCache` forwards the client cleanup script's
  `-IncludeInstallerCache` option.
- `-PurgeServerProgramData` removes `C:\ProgramData\DuressAlert` after the
  server uninstall/restore step.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeClientInstallerCache,
    [switch]$PurgeServerProgramData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$clientCleanupScript = Join-Path $scriptRoot 'cleanup-duress-client-test-install.ps1'
$serverCleanupScript = Join-Path $scriptRoot 'uninstall-real-server.ps1'
$serverProgramDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'DuressAlert'

Write-Host 'Combined Duress server/client cleanup'
Write-Host ('Client cleanup script: ' + $clientCleanupScript)
Write-Host ('Server cleanup script: ' + $serverCleanupScript)

if (-not (Test-Path $clientCleanupScript)) {
    throw "Client cleanup script was not found at $clientCleanupScript"
}

if (-not (Test-Path $serverCleanupScript)) {
    throw "Server cleanup script was not found at $serverCleanupScript"
}

$clientArgs = @()
if ($IncludeClientInstallerCache) {
    $clientArgs += @{ IncludeInstallerCache = $true }
}
if ($WhatIfPreference) {
    $clientArgs += @{ WhatIf = $true }
}

Write-Host 'Running client cleanup...'
if ($clientArgs.Count -gt 0) {
    $mergedClientArgs = @{}
    foreach ($entry in $clientArgs) {
        foreach ($key in $entry.Keys) {
            $mergedClientArgs[$key] = $entry[$key]
        }
    }

    & $clientCleanupScript @mergedClientArgs
}
else {
    & $clientCleanupScript
}

Write-Host 'Running server cleanup...'
& $serverCleanupScript

if ($PurgeServerProgramData -and (Test-Path $serverProgramDataRoot)) {
    if ($PSCmdlet.ShouldProcess($serverProgramDataRoot, 'Remove server ProgramData root')) {
        Remove-Item -LiteralPath $serverProgramDataRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Combined cleanup completed.'
