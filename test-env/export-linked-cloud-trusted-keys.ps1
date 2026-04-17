param(
    [string]$OutputPath = '',
    [string]$DatabaseName = 'duress_cloud_dev',
    [string]$DatabaseUser = 'duress_app',
    [string]$DatabasePassword = 'DuressCloudLocal!2026',
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $scriptRoot 'sandbox\trusted-keys\TrustedLicenseKeys.xml'
}

if (-not (Test-Path $PsqlPath)) {
    throw "psql was not found at '$PsqlPath'."
}

$dir = Split-Path -Parent $OutputPath
if ($dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$sqlPath = $null
$env:PGPASSWORD = $DatabasePassword
try {
    $sql = @'
select "KeyId", "PublicKeyXml"
from "SigningKeyRecords"
where "Status" <> 'Compromised'
order by coalesce("ActivatedUtc", "CreatedUtc") desc, "CreatedUtc" desc;
'@

    $sqlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('duress-export-trusted-keys-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
    $rows = & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -F '|' -f $sqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to query signing keys from cloud.'
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$builder.AppendLine('<TrustedLicenseKeys>')

    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row)) {
            continue
        }

        $parts = $row.Split('|', 2)
        if ($parts.Count -lt 2) {
            continue
        }

        $keyId = $parts[0].Trim()
        $publicKeyXml = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($keyId) -or [string]::IsNullOrWhiteSpace($publicKeyXml)) {
            continue
        }

        [void]$builder.Append('  <Key id="').Append([System.Security.SecurityElement]::Escape($keyId)).AppendLine('">')
        [void]$builder.Append('    <PublicKeyXml><![CDATA[').Append($publicKeyXml).AppendLine(']]></PublicKeyXml>')
        [void]$builder.AppendLine('  </Key>')
    }

    [void]$builder.AppendLine('</TrustedLicenseKeys>')
    Set-Content -Path $OutputPath -Value $builder.ToString() -Encoding UTF8

    Write-Host ('Trusted key bundle exported: ' + $OutputPath)
}
finally {
    if ($sqlPath) {
        Remove-Item $sqlPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
