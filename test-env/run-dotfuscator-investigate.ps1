param(
    [ValidateSet("client", "server")]
    [string]$Target,

    [string]$DotfuscatorCliPath = $(if ($env:DURESS_DOTFUSCATOR_CLI) { $env:DURESS_DOTFUSCATOR_CLI } else { "C:\Program Files (x86)\PreEmptive Protection Dotfuscator Professional 7.5.0\dotfuscator.exe" })
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $DotfuscatorCliPath)) {
    throw "Dotfuscator CLI was not found at $DotfuscatorCliPath"
}

switch ($Target) {
    "client" {
        $configPath = "C:\OLDD\Duress\Duress2025\scripts\dotfuscator-client-config.xml"
    }
    "server" {
        $configPath = "C:\OLDD\Duress\_external\DuressServer2025\scripts\dotfuscator-server-config.xml"
    }
}

if (!(Test-Path $configPath)) {
    throw "Starter config was not found: $configPath. Run generate-dotfuscator-starter-configs.ps1 first."
}

& $DotfuscatorCliPath /i /v $configPath
if ($LASTEXITCODE -ne 0) {
    throw "Dotfuscator investigate pass failed for $Target."
}

Write-Host "Dotfuscator investigate pass succeeded for $Target."
