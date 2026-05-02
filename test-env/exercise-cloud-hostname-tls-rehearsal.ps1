param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\cloud-hostname-tls\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
    [string]$AdminHost = "licenses.localtest.me",
    [string]$CustomerHost = "portal.localtest.me",
    [int]$Port = 5186,
    [switch]$RestoreDefaultCloud
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $PSScriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$startCloudScript = Join-Path $cloudRoot "scripts\start-duress-cloud.ps1"
$verifyCloudScript = Join-Path $cloudRoot "scripts\verify-duress-cloud.ps1"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$summaryPath = Join-Path $OutputRoot "CLOUD_HOSTNAME_TLS_REHEARSAL_SUMMARY.md"
$certPath = Join-Path $OutputRoot "duresscloud-rehearsal.pfx"
$certPasswordPlain = "DuressCloudTlsRehearsal123"
$certPassword = ConvertTo-SecureString -String $certPasswordPlain -AsPlainText -Force
$certFriendlyName = "Duress Cloud TLS rehearsal $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$createdCert = $null

function Invoke-HttpsRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $tempBody = Join-Path ([System.IO.Path]::GetTempPath()) ("duress-cloud-rehearsal-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
        try {
            $statusCode = & $curl.Source -k -sS -L --max-time 15 -o $tempBody -w "%{http_code}" $Uri
            $content = if (Test-Path -LiteralPath $tempBody) { Get-Content -LiteralPath $tempBody -Raw } else { "" }
            return [pscustomobject]@{
                StatusCode = [int]$statusCode
                Content = $content
            }
        }
        finally {
            Remove-Item -LiteralPath $tempBody -Force -ErrorAction SilentlyContinue
        }
    }

    $previousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        return Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15
    }
    finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCallback
    }
}

try {
    Write-Host "Creating local TLS rehearsal certificate..."
    $createdCert = New-SelfSignedCertificate `
        -DnsName @($AdminHost, $CustomerHost, "localhost") `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -FriendlyName $certFriendlyName `
        -NotAfter (Get-Date).AddDays(14)

    Export-PfxCertificate `
        -Cert $createdCert `
        -FilePath $certPath `
        -Password $certPassword | Out-Null

    if (-not (Test-Path -LiteralPath $certPath)) {
        throw "Failed to export rehearsal certificate to $certPath"
    }

    $adminBaseUrl = "https://$AdminHost`:$Port"
    $customerBaseUrl = "https://$CustomerHost`:$Port"

    Write-Host "Starting Duress Cloud with hostname/TLS rehearsal settings..."
    & $startCloudScript `
        -Scheme https `
        -PublicHost $AdminHost `
        -AdminBaseUrl $adminBaseUrl `
        -CustomerBaseUrl $customerBaseUrl `
        -CertificatePath $certPath `
        -CertificatePassword $certPasswordPlain `
        -Port $Port `
        -SkipBootstrap `
        -SkipCertificateCheck

    Write-Host "Verifying admin hostname over HTTPS..."
    & $verifyCloudScript `
        -Scheme https `
        -PublicHost $AdminHost `
        -Port $Port `
        -SkipCertificateCheck

    $portalLoginUrl = "$customerBaseUrl/Portal/Login"
    $portalCssUrl = "$customerBaseUrl/css/site.css"
    $portalLogin = Invoke-HttpsRequest -Uri $portalLoginUrl
    $portalCss = Invoke-HttpsRequest -Uri $portalCssUrl

    if ($portalLogin.StatusCode -ne 200) {
        throw "Portal login did not return 200 at $portalLoginUrl"
    }

    if ($portalCss.StatusCode -ne 200) {
        throw "Portal CSS did not return 200 at $portalCssUrl"
    }

    $lines = @(
        "# Cloud Hostname/TLS Rehearsal Summary",
        "",
        "- Timestamp: $(Get-Date -Format 'u')",
        "- Admin host: $AdminHost",
        "- Customer host: $CustomerHost",
        "- Port: $Port",
        "- Certificate path: $certPath",
        "- Admin base URL: $adminBaseUrl",
        "- Customer base URL: $customerBaseUrl",
        "",
        "## Checks",
        "",
        "- Duress Cloud started with direct HTTPS on Kestrel using a local self-signed PFX.",
        "- Admin health, CSS, and management login verified over `https://$AdminHost` with certificate bypass for local rehearsal.",
        "- Customer portal login and CSS verified over `https://$CustomerHost` with the same rehearsal certificate.",
        "- This confirms hostname-driven link generation and HTTPS endpoint reachability are no longer tied to the temporary LAN IP model."
    )

    $lines | Set-Content -Path $summaryPath
    Write-Host "Hostname/TLS rehearsal summary written to $summaryPath"
}
finally {
    if ($createdCert) {
        Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $createdCert.Thumbprint) -Force -ErrorAction SilentlyContinue
    }

    if ($RestoreDefaultCloud) {
        Write-Host "Restoring default local HTTP cloud host..."
        & $startCloudScript -Port $Port -SkipBootstrap
        & $verifyCloudScript -Port $Port
    }
}
