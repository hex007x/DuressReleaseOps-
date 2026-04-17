param(
    [string]$RotatedKeyId = 'emergency-2026-04',
    [string]$CustomerId = 'b6a76a46-8c9c-4bed-b3ea-f72dad9ea48a',
    [string]$CustomerName = 'Contoso Medical',
    [string]$LicenseSerial = 'DEV-LIC-ROTATED-0001',
    [int]$MaxClients = 9,
    [int]$ValidDays = 365,
    [string]$DatabaseName = 'duress_cloud_dev',
    [string]$DatabaseUser = 'duress_app',
    [string]$DatabasePassword = 'DuressCloudLocal!2026',
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\16\bin\psql.exe',
    [string]$ServerExePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$exportTrustedKeysScript = Join-Path $scriptRoot 'export-linked-cloud-trusted-keys.ps1'
$issueLocalCloudLicenseScript = Join-Path (Join-Path $workspaceRoot 'DuressCloud') 'scripts\issue-local-cloud-license.ps1'

if (-not (Test-Path $PsqlPath)) {
    throw "psql was not found at '$PsqlPath'."
}

if ([string]::IsNullOrWhiteSpace($ServerExePath)) {
    $ServerExePath = Join-Path $workspaceRoot '_external\DuressServer2025\DuressServer2025\bin\Debug\DuressServer.exe'
}

if (-not (Test-Path $ServerExePath)) {
    throw "Server executable not found at '$ServerExePath'."
}

$sandboxRoot = Join-Path (Join-Path $scriptRoot 'sandbox\trusted-key-rotation') ([Guid]::NewGuid().ToString('N'))
$privateKeyPath = Join-Path $sandboxRoot 'rotated-private-key.xml'
$licensePath = Join-Path $sandboxRoot 'rotated-license.xml'
$trustedKeysPath = Join-Path $sandboxRoot 'TrustedLicenseKeys.xml'
$isolatedServerRoot = Join-Path $sandboxRoot 'server-data'
$sqlPath = $null

New-Item -ItemType Directory -Force -Path $sandboxRoot | Out-Null

$previousDataRoot = $env:DURESS_SERVER_DATA_ROOT
$env:DURESS_SERVER_DATA_ROOT = $isolatedServerRoot
New-Item -ItemType Directory -Force -Path $isolatedServerRoot | Out-Null

[System.Reflection.Assembly]::LoadFrom($ServerExePath) | Out-Null
[DuressAlert.ConfigManager]::EnsureFoldersExist()
$fingerprint = [DuressAlert.LicenseManager]::GetServerFingerprint()

$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048)
try {
    $privateKeyXml = $rsa.ToXmlString($true)
    $publicKeyXml = $rsa.ToXmlString($false)
}
finally {
    $rsa.Dispose()
}

Set-Content -Path $privateKeyPath -Value $privateKeyXml -Encoding UTF8

$env:PGPASSWORD = $DatabasePassword
try {
    $escapedPrivate = $privateKeyXml.Replace("'", "''")
    $escapedPublic = $publicKeyXml.Replace("'", "''")
    $escapedKeyId = $RotatedKeyId.Replace("'", "''")
    $sql = @"
update "SigningKeyRecords"
set "PrivateKeyXml" = '$escapedPrivate',
    "PublicKeyXml" = '$escapedPublic',
    "Status" = 'Retired',
    "Notes" = 'Local trusted-key rotation rehearsal',
    "RetiredUtc" = now()
where "KeyId" = '$escapedKeyId';

insert into "SigningKeyRecords"
    ("Id", "KeyId", "DisplayName", "PrivateKeyXml", "PublicKeyXml", "Status", "CreatedByEmail", "Notes", "CreatedUtc", "ActivatedUtc", "RetiredUtc", "LastUsedUtc")
select gen_random_uuid(),
       '$escapedKeyId',
       'Emergency rotation key',
       '$escapedPrivate',
       '$escapedPublic',
       'Retired',
       'system@duresscloud.local',
       'Local trusted-key rotation rehearsal',
       now(),
       null,
       now(),
       null
where not exists (
    select 1 from "SigningKeyRecords" where "KeyId" = '$escapedKeyId'
);
"@

    $sqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-insert-rotated-key-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -f $sqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to seed the rotated signing key record into cloud data.'
    }
}
finally {
    if ($sqlPath) {
        Remove-Item $sqlPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

powershell -ExecutionPolicy Bypass -File $exportTrustedKeysScript `
    -OutputPath $trustedKeysPath `
    -DatabaseName $DatabaseName `
    -DatabaseUser $DatabaseUser `
    -DatabasePassword $DatabasePassword `
    -PsqlPath $PsqlPath

powershell -ExecutionPolicy Bypass -File $issueLocalCloudLicenseScript `
    -LicenseSerial $LicenseSerial `
    -CustomerId $CustomerId `
    -CustomerName $CustomerName `
    -ServerFingerprint $fingerprint `
    -KeyId $RotatedKeyId `
    -MaxClients $MaxClients `
    -ValidDays $ValidDays `
    -KeyPath $privateKeyPath `
    -OutputPath $licensePath

try {
    [DuressAlert.ConfigManager]::EnsureFoldersExist()

    $importMessageWithoutBundle = ''
    $importOkWithoutBundle = [DuressAlert.LicenseManager]::ImportSignedLicense($licensePath, [ref]$importMessageWithoutBundle)

    Copy-Item -Path $trustedKeysPath -Destination (Join-Path $isolatedServerRoot 'TrustedLicenseKeys.xml') -Force

    $importMessageWithBundle = ''
    $importOkWithBundle = [DuressAlert.LicenseManager]::ImportSignedLicense($licensePath, [ref]$importMessageWithBundle)
    $licenseInfo = [DuressAlert.LicenseManager]::GetLicenseInfo()
}
finally {
    $env:DURESS_SERVER_DATA_ROOT = $previousDataRoot
}

Write-Host 'Trusted-key rotation rehearsal'
Write-Host ('Sandbox root: ' + $sandboxRoot)
Write-Host ('Trusted bundle: ' + $trustedKeysPath)
Write-Host ('Rotated license: ' + $licensePath)
Write-Host ''
Write-Host ('Import without trusted bundle: ' + $importOkWithoutBundle)
Write-Host ('Message without trusted bundle: ' + $importMessageWithoutBundle)
Write-Host ('Import with trusted bundle: ' + $importOkWithBundle)
Write-Host ('Message with trusted bundle: ' + $importMessageWithBundle)

if ($licenseInfo) {
    Write-Host ('Imported license ID: ' + $licenseInfo.LicenseId)
    Write-Host ('Imported customer: ' + $licenseInfo.CustomerName)
    Write-Host ('Imported max clients: ' + $licenseInfo.MaxClients)
    Write-Host ('Imported status: ' + $licenseInfo.StatusMessage)
}

if ($importOkWithoutBundle) {
    throw 'Rotated license unexpectedly imported without the trusted key bundle.'
}

if ($importMessageWithoutBundle -notmatch 'Unknown signing key id') {
    throw 'Rotated license rejection did not report the missing signing key id as expected.'
}

if (-not $importOkWithBundle) {
    throw "Rotated license import still failed after deploying the trusted key bundle. $importMessageWithBundle"
}
