param(
    [int]$WaitSeconds = 75,
    [int]$MaxClients = 6,
    [int]$ValidDays = 365
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$programDataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert"
$signedLicenseFile = Join-Path $programDataRoot "License.v3.xml"
$runtimeStatusFile = Join-Path $programDataRoot "LicenseRuntimeStatus.xml"
$backupRoot = Join-Path $scriptRoot "sandbox\runtime\cloud-issued-license"
$backupLicense = Join-Path $backupRoot "License.v3.backup.xml"
$portalRenewed = Join-Path $scriptRoot "sandbox\runtime\license-portal\renewed-license.xml"

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

if (-not (Test-Path $signedLicenseFile)) {
    throw "Installed license not found: $signedLicenseFile"
}

Copy-Item -Path $signedLicenseFile -Destination $backupLicense -Force
[xml]$installed = Get-Content $signedLicenseFile
$fingerprint = $installed.SelectSingleNode("/License/ServerFingerprint").InnerText
$licenseSerial = $installed.SelectSingleNode("/License/LicenseId").InnerText
$customerName = $installed.SelectSingleNode("/License/CustomerName").InnerText
$customerId = $installed.SelectSingleNode("/License/CustomerId").InnerText
$previousMaxClients = $installed.SelectSingleNode("/License/MaxClients").InnerText

try {
    & "C:\OLDD\Duress\DuressCloud\scripts\issue-local-cloud-license.ps1" `
        -LicenseSerial $licenseSerial `
        -CustomerId $customerId `
        -CustomerName $customerName `
        -ServerFingerprint $fingerprint `
        -MaxClients $MaxClients `
        -ValidDays $ValidDays `
        -OutputPath "C:\OLDD\Duress\DuressCloud\artifacts\License.v3.xml"

    & (Join-Path $scriptRoot "prepare-license-portal.ps1")
    & (Join-Path $scriptRoot "sync-cloud-license-to-portal.ps1") -Target renewed
    & (Join-Path $scriptRoot "start-license-portal.ps1")
    & (Join-Path $scriptRoot "configure-real-server-license-portal.ps1") -CheckHours 1
    & (Join-Path $scriptRoot "set-license-portal-response.ps1") -Mode renewed | Out-Null

    Restart-Service -Name DuressAlertService -Force
    Start-Sleep -Seconds $WaitSeconds

    [xml]$refreshed = Get-Content $signedLicenseFile
    [xml]$runtime = Get-Content $runtimeStatusFile

    [pscustomobject]@{
        PreviousMaxClients = $previousMaxClients
        RefreshedMaxClients = $refreshed.SelectSingleNode("/License/MaxClients").InnerText
        RefreshedLicenseId = $refreshed.SelectSingleNode("/License/LicenseId").InnerText
        RefreshedFingerprint = $refreshed.SelectSingleNode("/License/ServerFingerprint").InnerText
        LastCloudCheckResult = $runtime.SelectSingleNode("/LicenseRuntimeStatus/LastCloudCheckResult").InnerText
        LastCloudLicenseState = $runtime.SelectSingleNode("/LicenseRuntimeStatus/LastCloudLicenseState").InnerText
        PortalRenewedPath = $portalRenewed
    }
}
finally {
    if (Test-Path $backupLicense) {
        Copy-Item -Path $backupLicense -Destination $signedLicenseFile -Force
        Restart-Service -Name DuressAlertService -Force
    }
}
