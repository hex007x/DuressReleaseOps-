param(
    [string]$CloudCheckinUrl = 'http://localhost:5190/api/licensing/checkin',
    [string]$LicenseSerial = 'DEV-LIC-0001',
    [string]$CustomerId = 'b6a76a46-8c9c-4bed-b3ea-f72dad9ea48a',
    [string]$CustomerName = 'Contoso Medical',
    [string]$SigningKeyId = 'linked-checkin-2026-03',
    [int]$MaxClients = 9,
    [int]$ValidDays = 400,
    [string]$ServerExePath = '',
    [switch]$SkipCloudStartup,
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
$artifactRoot = Join-Path (Join-Path $scriptRoot 'sandbox\linked-cloud-checkin') ([Guid]::NewGuid().ToString('N'))
$licenseArtifactPath = Join-Path $artifactRoot 'License.v3.xml'
$trustedKeysArtifactPath = Join-Path $artifactRoot 'TrustedLicenseKeys.xml'
$privateKeyPath = Join-Path $artifactRoot 'linked-checkin-private-key.xml'
$exportTrustedKeysScript = Join-Path $scriptRoot 'export-linked-cloud-trusted-keys.ps1'
$serverCloudCheckinScript = Join-Path $scriptRoot 'exercise-server-cloud-checkin.ps1'
$issueLocalCloudLicenseScript = Join-Path $cloudRoot 'scripts\issue-local-cloud-license.ps1'

if ([string]::IsNullOrWhiteSpace($ServerExePath)) {
    $ServerExePath = Join-Path $workspaceRoot '_external\DuressServer2025\DuressServer2025\bin\Debug\DuressServer.exe'
}

if (-not (Test-Path $ServerExePath)) {
    throw "Server executable not found at '$ServerExePath'."
}

if (-not (Test-Path $PsqlPath)) {
    throw "psql was not found at '$PsqlPath'."
}

[void](New-Item -ItemType Directory -Force -Path $artifactRoot)

[System.Reflection.Assembly]::LoadFrom($ServerExePath) | Out-Null
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

$job = $null

$sqlPath = $null
$signingKeySqlPath = $null
$verifySqlPath = $null
$env:PGPASSWORD = $DatabasePassword

try {
    if (-not $SkipCloudStartup) {
        $job = Start-Job -ScriptBlock {
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
    }

    $ready = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        try {
            if ((Invoke-WebRequest -UseBasicParsing http://localhost:5186/ready -TimeoutSec 5).StatusCode -eq 200) {
                $ready = $true
                break
            }
        }
        catch {
        }
    }

    if (-not $ready) {
        throw 'Cloud app did not become ready on localhost:5186.'
    }

    $escapedPrivate = $privateKeyXml.Replace("'", "''")
    $escapedPublic = $publicKeyXml.Replace("'", "''")
    $escapedKeyId = $SigningKeyId.Replace("'", "''")
    $signingKeySql = @"
update "SigningKeyRecords"
set "PrivateKeyXml" = '$escapedPrivate',
    "PublicKeyXml" = '$escapedPublic',
    "Status" = 'Retired',
    "Notes" = 'Linked cloud check-in rehearsal',
    "RetiredUtc" = now()
where "KeyId" = '$escapedKeyId';

insert into "SigningKeyRecords"
    ("Id", "KeyId", "DisplayName", "PrivateKeyXml", "PublicKeyXml", "Status", "CreatedByEmail", "Notes", "CreatedUtc", "ActivatedUtc", "RetiredUtc", "LastUsedUtc")
select gen_random_uuid(),
       '$escapedKeyId',
       'Linked cloud check-in rehearsal key',
       '$escapedPrivate',
       '$escapedPublic',
       'Retired',
       'system@duresscloud.local',
       'Linked cloud check-in rehearsal',
       now(),
       null,
       now(),
       null
where not exists (
    select 1 from "SigningKeyRecords" where "KeyId" = '$escapedKeyId'
);
"@

    $signingKeySqlPath = Join-Path $env:TEMP ('duress-cloud-checkin-key-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $signingKeySqlPath -Value $signingKeySql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $signingKeySqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to seed the cloud check-in signing key data.'
    }

    powershell -ExecutionPolicy Bypass -File $exportTrustedKeysScript `
        -OutputPath $trustedKeysArtifactPath `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabasePassword $DatabasePassword `
        -PsqlPath $PsqlPath

    powershell -ExecutionPolicy Bypass -File $issueLocalCloudLicenseScript `
        -LicenseSerial $LicenseSerial `
        -CustomerId $CustomerId `
        -CustomerName $CustomerName `
        -ServerFingerprint $fingerprint `
        -KeyId $SigningKeyId `
        -MaxClients $MaxClients `
        -ValidDays $ValidDays `
        -KeyPath $privateKeyPath `
        -OutputPath $licenseArtifactPath

$xml = Get-Content $licenseArtifactPath -Raw
$xmlSql = $xml.Replace("'", "''")
$fingerprintSql = $fingerprint.Replace("'", "''")
$expiryUtc = [DateTimeOffset]::UtcNow.AddDays($ValidDays).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')

$sql = @"
update "SystemInstallations"
set "ServerFingerprint" = '$fingerprintSql',
    "LastCheckinResult" = 'Prepared for cloud check-in test'
where "SystemName" = 'Main Reception Server';

update "Licenses"
set "SignedLicenseXml" = '$xmlSql',
    "LicensedSeatCount" = $MaxClients,
    "ExpiryUtc" = '$expiryUtc',
    "Status" = 'Active'
where "LicenseSerial" = '$LicenseSerial';
"@

    $sqlPath = Join-Path $env:TEMP ('duress-cloud-checkin-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $sqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to seed the cloud check-in data.'
    }

    powershell -ExecutionPolicy Bypass -File $serverCloudCheckinScript `
        -CloudCheckinUrl $CloudCheckinUrl `
        -SignedLicensePath $licenseArtifactPath `
        -TrustedKeysPath $trustedKeysArtifactPath `
        -ServerExePath $ServerExePath

    $verifySqlPath = Join-Path $env:TEMP ('duress-cloud-checkin-verify-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $verifySqlPath -Value 'select "PublicIp", "LocalIp", "LocalIpList", "HealthStatus", "IssueCountSinceLastReport", "IssuesSummary", "ResultMessage" from "LicenseCheckins" order by "CreatedUtc" desc limit 1;' -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $verifySqlPath
}
finally {
    if ($sqlPath -and (Test-Path $sqlPath)) {
        Remove-Item $sqlPath -Force -ErrorAction SilentlyContinue
    }

    if ($signingKeySqlPath -and (Test-Path $signingKeySqlPath)) {
        Remove-Item $signingKeySqlPath -Force -ErrorAction SilentlyContinue
    }

    if ($verifySqlPath -and (Test-Path $verifySqlPath)) {
        Remove-Item $verifySqlPath -Force -ErrorAction SilentlyContinue
    }

    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue

    if ($job) {
        Stop-Job $job -ErrorAction SilentlyContinue | Out-Null
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
