param(
    [string]$SystemName = 'Main Reception Server',
    [string]$ClaimToken = 'DEV-CLAIM-DEFAULT',
    [string]$CloudClaimUrl = 'http://localhost:5186/api/systems/claim',
    [string]$ServerExePath = '',
    [switch]$ExpectTrialLicense,
    [string]$DatabaseName = 'duress_cloud_dev',
    [string]$DatabaseUser = 'duress_app',
    [string]$DatabasePassword = 'DuressCloudLocal!2026',
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$serverCloudClaimScript = Join-Path $scriptRoot 'exercise-server-cloud-claim.ps1'

if ([string]::IsNullOrWhiteSpace($ServerExePath)) {
    $ServerExePath = Join-Path $workspaceRoot '_external\DuressServer2025\DuressServer2025\bin\Debug\DuressServer.exe'
}

if (-not (Test-Path $PsqlPath)) {
    throw "psql was not found at '$PsqlPath'."
}

$sha256 = [System.Security.Cryptography.SHA256Managed]::new()
try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ClaimToken))
}
finally {
    $sha256.Dispose()
}

$hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')

$sql = @'
update "SystemInstallations"
set "ClaimTokenHash" = '__HASH__',
    "ServerFingerprint" = 'pending-dev-claim',
    "LastSeenMachineId" = '',
    "LocalIpLastSeen" = '',
    "PublicIpLastSeen" = '',
    "CheckinCount" = 0,
    "LastCheckinResult" = 'Pending linked cloud claim test'
where "SystemName" = '__SYSTEMNAME__';

select "SystemName", "ServerFingerprint", "CheckinCount", "LastCheckinResult"
from "SystemInstallations"
where "SystemName" = '__SYSTEMNAME__';
'@

$sql = $sql.Replace('__HASH__', $hash).Replace('__SYSTEMNAME__', $SystemName.Replace("'", "''"))

$prepareSqlPath = $null
$verifySqlPath = $null

$env:PGPASSWORD = $DatabasePassword
try {
    $prepareSqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-prepare-claim-' + [Guid]::NewGuid().ToString('N') + '.sql')
    $verifySqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-verify-claim-' + [Guid]::NewGuid().ToString('N') + '.sql')

    Set-Content -Path $prepareSqlPath -Value $sql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $prepareSqlPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to prepare the cloud system record for claim."
    }

    powershell -ExecutionPolicy Bypass -File $serverCloudClaimScript `
        -CloudClaimUrl $CloudClaimUrl `
        -ClaimToken $ClaimToken `
        -ServerExePath $ServerExePath

    $verifySql = @'
select "SystemName",
       "ServerFingerprint",
       "LastSeenMachineId",
       "ProductVersionLastSeen",
       "LocalIpLastSeen",
       "CheckinCount",
       "LastCheckinResult",
       "CurrentLicenseId"
from "SystemInstallations"
where "SystemName" = '__SYSTEMNAME__';
'@

    $verifySql = $verifySql.Replace('__SYSTEMNAME__', $SystemName.Replace("'", "''"))
    Set-Content -Path $verifySqlPath -Value $verifySql -Encoding UTF8
    $systemState = & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F '|' -f $verifySqlPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to verify the claimed cloud system record."
    }

    if ($ExpectTrialLicense) {
        $licenseVerifySql = @'
select l."LicenseSerial",
       l."Status",
       l."LicensedSeatCount",
       l."ExpiryUtc"
from "SystemInstallations" s
join "Licenses" l on l."Id" = s."CurrentLicenseId"
where s."SystemName" = '__SYSTEMNAME__';
'@

        $licenseVerifySql = $licenseVerifySql.Replace('__SYSTEMNAME__', $SystemName.Replace("'", "''"))
        $licenseVerifySqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-verify-claim-license-' + [Guid]::NewGuid().ToString('N') + '.sql')
        Set-Content -Path $licenseVerifySqlPath -Value $licenseVerifySql -Encoding UTF8
        try {
            & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F '|' -f $licenseVerifySqlPath
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to verify the claimed trial license record."
            }
        }
        finally {
            Remove-Item $licenseVerifySqlPath -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    Remove-Item $prepareSqlPath -Force -ErrorAction SilentlyContinue
    Remove-Item $verifySqlPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
