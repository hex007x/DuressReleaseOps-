param(
    [string]$SystemName = 'Main Reception Server',
    [string]$ClaimToken = 'DEV-CLAIM-DEFAULT',
    [string]$CloudClaimUrl = 'http://localhost:5186/api/systems/claim',
    [string]$CloudCheckinUrl = 'http://localhost:5186/api/licensing/checkin',
    [string]$LicenseSerial = 'DEV-LIC-0001',
    [string]$CustomerId = 'b6a76a46-8c9c-4bed-b3ea-f72dad9ea48a',
    [string]$CustomerName = 'Contoso Medical',
    [int]$RenewedMaxClients = 9,
    [int]$RenewedValidDays = 400,
    [switch]$IncludeTrialClaim,
    [switch]$IncludeRenewalRefresh = $true,
    [string]$DatabaseName = 'duress_cloud_dev',
    [string]$DatabaseUser = 'duress_app',
    [string]$DatabasePassword = 'DuressCloudLocal!2026',
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot 'DuressCloud'
$cloudExe = Join-Path $cloudRoot 'src\DuressCloud.Web\bin\Debug\net8.0\DuressCloud.Web.exe'
$cloudJob = $null
$linkedClaimScript = Join-Path $scriptRoot 'exercise-linked-cloud-claim.ps1'
$linkedCheckinScript = Join-Path $scriptRoot 'exercise-linked-cloud-checkin.ps1'

Write-Host 'Duress linked cloud lifecycle rehearsal'
Write-Host ('System: ' + $SystemName)
Write-Host ('Cloud claim URL: ' + $CloudClaimUrl)
Write-Host ('Cloud check-in URL: ' + $CloudCheckinUrl)
Write-Host ''

try {
    $ready = $false
    try {
        $ready = (Invoke-WebRequest -UseBasicParsing 'http://localhost:5186/ready' -TimeoutSec 5).StatusCode -eq 200
    }
    catch {
        $ready = $false
    }

    if (-not $ready) {
        Write-Host 'Starting local Duress Cloud for lifecycle rehearsal...'
        $cloudJob = Start-Job -ScriptBlock {
            param($CloudRoot, $CloudExe)

            Set-Location $CloudRoot
            $env:ASPNETCORE_ENVIRONMENT = 'Development'
            $env:ConnectionStrings__CloudPlatform = 'Host=localhost;Port=5432;Database=duress_cloud_dev;Username=duress_app;Password=DuressCloudLocal!2026'
            $env:CloudPlatform__LicenseSigningKeyPath = (Join-Path $CloudRoot 'keys\dev-license-private-key.xml')
            $env:CloudPlatform__SeedDemoData = 'true'
            if (Test-Path $CloudExe) {
                & $CloudExe --urls http://localhost:5186
            }
            else {
                & 'C:\Program Files\dotnet\dotnet.exe' run --project .\src\DuressCloud.Web\DuressCloud.Web.csproj -- --urls http://localhost:5186
            }
        } -ArgumentList $cloudRoot, $cloudExe

        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 2
            try {
                if ((Invoke-WebRequest -UseBasicParsing 'http://localhost:5186/ready' -TimeoutSec 5).StatusCode -eq 200) {
                    $ready = $true
                    break
                }
            }
            catch {
            }
        }
    }

    if (-not $ready) {
        throw 'Duress Cloud did not become ready on http://localhost:5186.'
    }

    if ($IncludeTrialClaim) {
        Write-Host 'Step 1. Trial claim/bootstrap'
        powershell -ExecutionPolicy Bypass -File $linkedClaimScript `
            -SystemName $SystemName `
            -ClaimToken $ClaimToken `
            -CloudClaimUrl $CloudClaimUrl `
            -ExpectTrialLicense `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabasePassword $DatabasePassword `
            -PsqlPath $PsqlPath
        Write-Host ''
    }

    if ($IncludeRenewalRefresh) {
        Write-Host 'Step 2. Renewal refresh / cloud check-in'
        powershell -ExecutionPolicy Bypass -File $linkedCheckinScript `
            -CloudCheckinUrl $CloudCheckinUrl `
            -LicenseSerial $LicenseSerial `
            -CustomerId $CustomerId `
            -CustomerName $CustomerName `
            -MaxClients $RenewedMaxClients `
            -ValidDays $RenewedValidDays `
            -SkipCloudStartup `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabasePassword $DatabasePassword `
            -PsqlPath $PsqlPath
        Write-Host ''
    }

    Write-Host 'Lifecycle rehearsal completed.'
}
finally {
    if ($cloudJob) {
        Stop-Job $cloudJob -ErrorAction SilentlyContinue | Out-Null
        Receive-Job $cloudJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $cloudJob -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
