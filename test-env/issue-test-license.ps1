param(
  [string]$CustomerId = "TEST-CUSTOMER",
  [string]$CustomerName = "Local Test Customer",
  [string]$LicenseId = "LIC-LOCAL-TEST",
  [ValidateSet("Subscription", "Full", "Trial", "Demo")][string]$LicenseType = "Subscription",
  [int]$MaxClients = 2,
  [int]$ValidDays = 30,
  [string]$Features = "email,slack,teams,google_chat",
  [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
  $OutputPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) "DuressAlert\License.v3.xml"
}

$privateKeyXml = "<RSAKeyValue><Modulus>94XQv4u6oMF9xhNuOLb9Oq7AymWMXvcIjBFvszHYOZ03/ibIO9NF9cGeuE9dLbe3G5TBgR3559vLl/uLHz3i11HUsP/74oa5snCNoS60bpjHlZj0jHD1z4+VzaTkx3o6pYz2AwMBh+y9DfRl2Ht0/i50gYna3lzJeuqIM1n2L+hCb/MHtfQDHXOXQLblSjcag41Y24Q+wUMYGJcJEbJOq2F5c5io7qlKdUKgUY/eadqJvcg/DI+CL3d2u5LmkKLiBBapi7iEZlx/kYjHopJvt7scOGXIwwL+Pzo1Pc65THIQWotVstLREQWnvuLxuXXY6UaDA0RZtVhXcBNuLQiH8Q==</Modulus><Exponent>AQAB</Exponent><P>98p72gS3ouEcN1qTdrSJ399mTW4x5HyZ8ReEr3MCde9+Alf6He33j1FE7QH9THUfRvw4W3ACvp+i3N5mEGCTXoqxwHxGTJTyHSCqpSZtAhyWGek/bNMl3CJUbOICS7SXJKlqYw0mG4deFkkefnY24koBiaNsQ318nYyLydy7Ri8=</P><Q>/7kOhRIWhGseFRBR+Nz+Syx8ABl/sCbhyG0RE0ViEIroIDOZlAno3yVhng2zJQT9/6/vb4/CT44766OTeTRHVNlXxv74uaG51sYfG3DJDSf43ujo9fBQasUsg5/TFwO9Mv0Fl/KjeHvs1mo2o6Qu+NREiKt8raNH71p6WlYLq98=</Q><DP>S1iuwGSe0lBRHCPWo0nSgtiTawgO88NPrBfSqOb34JSqZFwMGf26QUIdC1SHiTA0Com3OVad/wjbpP2bW2+CYEUcN8OSPMctt92vBfjhPLskiUx7lMO/x2hI87Llr8+CBgvd5bCh3c0TtwMU2q9nkPef8BJZYUxPEDkkaIVODNE=</DP><DQ>Nz90+pz4zm0SF7zp6Nld+0HGHINlydnsp8+gg8hWsnpAQkzDnm8xp5w85dfR32qfsbECCtlFQsjY+0Tg5Ku9yYAXbb/CXuCo9NTi/Zu1ZClBpG8vfYsI5LhqsJlEEtHU+4IcxkI+vRYRChXybhJXr5y0nc5m5mDDdtvWWVQDu4M=</DQ><InverseQ>tIy5mf1KfEc+IhBYaB8p+qPUXJAk7tMIx3P64PKNEEcsLn2UbLxqoeXn+I7LKnBlZRDOjAzPQkAJRXecwPqApEKkY3wTAwcgp74J15qB3IoeLWM4tQ+BJO4eKn/MV4qBnjFe0dejep7H+pQalaKQoyfK6Wq0bQ5Fg8V/fnXkqrk=</InverseQ><D>ncIyHANIvbDVIuu7cnZey4oZ4mX6o4Q7dFqgoMuCDqZ/y4KYWFj92/a93KbosnzHPdL/yfV7FCXoi0ONlinxbF8BepaMygIoVOybuEF2So8hld1Y8DIG2XWgeuM/1Uu4GU/QdHb0ANgIXt6IEwQMuvyM0Qs17kehOrBEgsYxvLHAyxCheF2+zoj/g2vu5fjJM7JWk+RO/I/XXem6Fq0WjPGEoHiZlwzJ+mssuUFXwy0TlCZ6ELTwXxwa3yc6NleOMABu16U3odmaCweZy8nix0U4gq9bVRcwu76falcusVSIJnLQyg93VErRcDnAPJcKoNn0+17PNvNDQTqxDcnDaQ==</D></RSAKeyValue>"

function Get-MachineId {
  $machineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction SilentlyContinue).MachineGuid
  $machineId = "{0}-{1}-{2}" -f $env:COMPUTERNAME, [Environment]::ProcessorCount, $machineGuid
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($machineId)
    $hash = $md5.ComputeHash($bytes)
    return -join ($hash | ForEach-Object { $_.ToString("X2") })
  } finally {
    $md5.Dispose()
  }
}

function Get-ServerFingerprint {
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-MachineId))
    $hash = $sha256.ComputeHash($bytes)
    return -join ($hash | ForEach-Object { $_.ToString("X2") })
  } finally {
    $sha256.Dispose()
  }
}

$issuedAt = [DateTime]::UtcNow
$expiresAt = if ($LicenseType -eq "Full") { [DateTime]::MaxValue } else { $issuedAt.AddDays($ValidDays) }
$fingerprint = Get-ServerFingerprint

$payloadLines = @(
  $LicenseId,
  $CustomerId,
  $CustomerName,
  $LicenseType,
  $issuedAt.ToString("o"),
  $expiresAt.ToString("o"),
  $MaxClients.ToString(),
  $fingerprint,
  $Features
)
$payload = [string]::Join("`n", $payloadLines)

$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
try {
  $rsa.FromXmlString($privateKeyXml)
  $signatureBytes = $rsa.SignData([System.Text.Encoding]::UTF8.GetBytes($payload), [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA256"))
  $signature = [Convert]::ToBase64String($signatureBytes)
} finally {
  $rsa.Dispose()
}

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<License>
  <LicenseId>$LicenseId</LicenseId>
  <CustomerId>$CustomerId</CustomerId>
  <CustomerName>$CustomerName</CustomerName>
  <LicenseType>$LicenseType</LicenseType>
  <IssuedAtUtc>$($issuedAt.ToString("o"))</IssuedAtUtc>
  <ExpiresAtUtc>$($expiresAt.ToString("o"))</ExpiresAtUtc>
  <MaxClients>$MaxClients</MaxClients>
  <ServerFingerprint>$fingerprint</ServerFingerprint>
  <Features>$Features</Features>
  <Signature>$signature</Signature>
</License>
"@

$dir = Split-Path -Parent $OutputPath
if ($dir) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Set-Content -Path $OutputPath -Value $xml -Encoding UTF8
Write-Host "Issued signed test license:" $OutputPath
Write-Host "Server fingerprint:" $fingerprint
