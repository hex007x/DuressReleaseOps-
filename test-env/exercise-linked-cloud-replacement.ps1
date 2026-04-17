param(
    [string]$SystemName = 'Main Reception Server',
    [string]$ReplacementClaimToken = 'DEV-REPLACEMENT-CLAIM',
    [string]$CloudClaimUrl = 'http://localhost:5186/api/systems/claim',
    [string]$ServerExePath = '',
    [string]$ReplacementFingerprint = 'REPLACEMENT-FINGERPRINT-DEV-001',
    [string]$ReplacementMachineName = 'replacement-server-dev',
    [string]$ReplacementProductVersion = '3.0.0-replacement',
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
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ReplacementClaimToken))
}
finally {
    $sha256.Dispose()
}

$hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')
$prepareSqlPath = $null
$verifySqlPath = $null
$schemaCheckSqlPath = $null

$env:PGPASSWORD = $DatabasePassword
try {
    $schemaCheckSql = @'
select column_name
from information_schema.columns
where table_name = 'SystemInstallations'
  and column_name in ('PreviousServerFingerprint', 'TransferWorkflowType', 'TransferPreparedUtc', 'TransferCompletedUtc', 'PreviousServerRetiredUtc')
order by column_name;
'@

    $schemaCheckSqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-replacement-schema-check-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $schemaCheckSqlPath -Value $schemaCheckSql -Encoding UTF8
    $schemaColumns = & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $schemaCheckSqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to inspect the cloud database schema for replacement workflow columns.'
    }

    $requiredColumns = @(
        'PreviousServerFingerprint',
        'PreviousServerRetiredUtc',
        'TransferCompletedUtc',
        'TransferPreparedUtc',
        'TransferWorkflowType'
    )

    foreach ($requiredColumn in $requiredColumns) {
        if ($schemaColumns -notcontains $requiredColumn) {
            throw "Cloud database is missing replacement workflow column '$requiredColumn'. Apply the latest Duress Cloud migrations before running this rehearsal."
        }
    }

    $prepareSql = @'
update "SystemInstallations"
set "ClaimTokenHash" = '__HASH__',
    "PreviousServerFingerprint" = "ServerFingerprint",
    "ServerFingerprint" = 'pending-dev-replacement',
    "Status" = 'Transferred',
    "TransferWorkflowType" = 'replacement',
    "TransferPreparedUtc" = now(),
    "TransferCompletedUtc" = null,
    "PreviousServerRetiredUtc" = null,
    "LastCheckinResult" = 'Replacement prepared. Waiting for new server claim.'
where "SystemName" = '__SYSTEMNAME__';

select "SystemName",
       "Status",
       "ServerFingerprint",
       "PreviousServerFingerprint",
       "TransferWorkflowType",
       "LastCheckinResult"
from "SystemInstallations"
where "SystemName" = '__SYSTEMNAME__';
'@

    $prepareSql = $prepareSql.Replace('__HASH__', $hash).Replace('__SYSTEMNAME__', $SystemName.Replace("'", "''"))
    $prepareSqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-prepare-replacement-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $prepareSqlPath -Value $prepareSql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F '|' -f $prepareSqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to prepare replacement workflow state in cloud.'
    }

    powershell -ExecutionPolicy Bypass -File $serverCloudClaimScript `
        -CloudClaimUrl $CloudClaimUrl `
        -ClaimToken $ReplacementClaimToken `
        -ServerExePath $ServerExePath

    $verifySql = @'
select "SystemName",
       "Status",
       "ServerFingerprint",
       "PreviousServerFingerprint",
       "TransferWorkflowType",
       "TransferPreparedUtc",
       "TransferCompletedUtc",
       "PreviousServerRetiredUtc",
       "LastCheckinResult"
from "SystemInstallations"
where "SystemName" = '__SYSTEMNAME__';
'@

    $verifySql = $verifySql.Replace('__SYSTEMNAME__', $SystemName.Replace("'", "''"))
    $verifySqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-verify-replacement-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $verifySqlPath -Value $verifySql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F '|' -f $verifySqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to verify replacement workflow state in cloud.'
    }
}
finally {
    if ($schemaCheckSqlPath) {
        Remove-Item $schemaCheckSqlPath -Force -ErrorAction SilentlyContinue
    }
    if ($prepareSqlPath) {
        Remove-Item $prepareSqlPath -Force -ErrorAction SilentlyContinue
    }
    if ($verifySqlPath) {
        Remove-Item $verifySqlPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
