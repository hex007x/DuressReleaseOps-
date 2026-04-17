param(
    [string]$DotfuscatorCliPath = $(if ($env:DURESS_DOTFUSCATOR_CLI) { $env:DURESS_DOTFUSCATOR_CLI } else { "C:\Program Files (x86)\PreEmptive Protection Dotfuscator Professional 7.5.0\dotfuscator.exe" })
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $DotfuscatorCliPath)) {
    throw "Dotfuscator CLI was not found at $DotfuscatorCliPath"
}

$clientExe = "C:\OLDD\Duress\Duress2025\Duress\bin\Release\Duress.exe"
$serverExe = "C:\OLDD\Duress\_external\DuressServer2025\DuressServer2025\bin\Release\DuressServer.exe"
$clientConfig = "C:\OLDD\Duress\Duress2025\scripts\dotfuscator-client-config.xml"
$serverConfig = "C:\OLDD\Duress\_external\DuressServer2025\scripts\dotfuscator-server-config.xml"
$clientOut = "C:\OLDD\Duress\temp\dotfuscator-client-out"
$serverOut = "C:\OLDD\Duress\temp\dotfuscator-server-out"

New-Item -ItemType Directory -Path $clientOut -Force | Out-Null
New-Item -ItemType Directory -Path $serverOut -Force | Out-Null

if (!(Test-Path $clientExe)) {
    throw "Client release executable not found: $clientExe"
}

if (!(Test-Path $serverExe)) {
    throw "Server release executable not found: $serverExe"
}

& $DotfuscatorCliPath /genconfig:$clientConfig /in:+$clientExe /out:$clientOut /rename:on /controlflow:low /encrypt:on /smart:on /suppress:on
if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate Dotfuscator client starter config."
}

& $DotfuscatorCliPath /genconfig:$serverConfig /in:+$serverExe /out:$serverOut /rename:on /controlflow:low /encrypt:on /smart:on /suppress:on
if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate Dotfuscator server starter config."
}

Write-Host "Generated starter configs:"
Write-Host "  $clientConfig"
Write-Host "  $serverConfig"
