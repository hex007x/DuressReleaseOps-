param(
    [string]$OutputRoot = 'C:\OLDD\Duress\test-env\sandbox\hardened-release',
    [string]$BuildScriptPath = 'C:\OLDD\Duress\_external\DuressServer2025\scripts\build-hardened-release.ps1'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BuildScriptPath)) {
    throw "Hardened release build script was not found at '$BuildScriptPath'."
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $resolvedOutputRoot | Out-Null

$releaseOutputRoot = Join-Path $resolvedOutputRoot 'server'
$requireOutputRoot = Join-Path $resolvedOutputRoot 'server-require-obfuscation'
$requireManifestPath = Join-Path $requireOutputRoot 'hardened-release-manifest.json'
$requireFailureMessage = ''
$requireFailureObserved = $false
$requireSuccessObserved = $false

Write-Host 'Running hardened release build rehearsal...'
powershell -ExecutionPolicy Bypass -File $BuildScriptPath -OutputRoot $releaseOutputRoot

$exePath = Join-Path $releaseOutputRoot 'DuressServer.exe'
$manifestPath = Join-Path $releaseOutputRoot 'hardened-release-manifest.json'

if (-not (Test-Path $exePath)) {
    throw "Expected hardened release executable was not created at '$exePath'."
}

if (-not (Test-Path $manifestPath)) {
    throw "Expected hardened release manifest was not created at '$manifestPath'."
}

Write-Host ''
Write-Host 'Running fail-closed obfuscation check...'
$stderrPath = Join-Path $resolvedOutputRoot 'server-require-obfuscation.stderr.log'
$stdoutPath = Join-Path $resolvedOutputRoot 'server-require-obfuscation.stdout.log'

if (Test-Path $stderrPath) {
    Remove-Item -LiteralPath $stderrPath -Force
}

if (Test-Path $stdoutPath) {
    Remove-Item -LiteralPath $stdoutPath -Force
}

$requireProcess = Start-Process -FilePath 'powershell' `
    -ArgumentList @(
        '-ExecutionPolicy', 'Bypass',
        '-File', $BuildScriptPath,
        '-OutputRoot', $requireOutputRoot,
        '-RequireObfuscation'
    ) `
    -Wait `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

$requireStdOut = if (Test-Path $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
$requireStdErr = if (Test-Path $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }

if ($requireStdOut) {
    Write-Host $requireStdOut.TrimEnd()
}

if ($requireStdErr) {
    Write-Host $requireStdErr.TrimEnd()
}

if ($requireProcess.ExitCode -ne 0) {
    $requireFailureObserved = $true
    $requireFailureMessage = ($requireStdOut + [Environment]::NewLine + $requireStdErr).Trim()
}
else {
    $requireSuccessObserved = $true
}

if ($requireFailureObserved) {
    if ($requireFailureMessage -notmatch 'Obfuscation was required') {
        throw "RequireObfuscation failed, but not with the expected fail-closed message. Actual: $requireFailureMessage"
    }
}
elseif ($requireSuccessObserved) {
    if (-not (Test-Path $requireManifestPath)) {
        throw "RequireObfuscation succeeded, but the expected manifest was not created at '$requireManifestPath'."
    }

    $requireManifest = Get-Content -LiteralPath $requireManifestPath -Raw | ConvertFrom-Json
    if (-not $requireManifest.ObfuscationRan) {
        throw 'RequireObfuscation succeeded, but the manifest did not record that obfuscation ran.'
    }
}
else {
    throw 'RequireObfuscation produced neither a successful obfuscated build nor an expected fail-closed error.'
}

Write-Host ''
Write-Host 'Hardened release rehearsal summary'
Write-Host ('Output root: ' + $releaseOutputRoot)
Write-Host ('Executable: ' + $exePath)
Write-Host ('Manifest: ' + $manifestPath)
Write-Host ('RequireObfuscation success observed: ' + $requireSuccessObserved)
Write-Host ('RequireObfuscation fail-closed observed: ' + $requireFailureObserved)
Write-Host ('RequireObfuscation message: ' + $requireFailureMessage)
