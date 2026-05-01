param(
  [Parameter(Mandatory = $true)][string]$ClientVersion,
  [Parameter(Mandatory = $true)][string]$ServerVersion,
  [string]$DatabaseName = "duress_cloud_dev",
  [string]$DatabaseUser = "duress_app",
  [string]$DatabasePassword = "DuressCloudLocal!2026",
  [string]$DatabaseHost = "localhost",
  [string]$CloudBaseUrl = "http://192.168.20.85:5186"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$installerRoot = Join-Path $cloudRoot "artifacts\installers"
$psql = "C:\Program Files\PostgreSQL\16\bin\psql.exe"

if (-not (Test-Path $psql)) {
  throw "psql.exe was not found at $psql"
}

function Invoke-PsqlRows {
  param([Parameter(Mandatory = $true)][string]$Sql)

  $tempSqlPath = Join-Path $env:TEMP ("duress-release-sql-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
  try {
    Set-Content -Path $tempSqlPath -Value $Sql -Encoding UTF8
    $env:PGPASSWORD = $DatabasePassword
    $output = & $psql -v ON_ERROR_STOP=1 -U $DatabaseUser -h $DatabaseHost -d $DatabaseName -t -A -F "|" -f $tempSqlPath
    if ($LASTEXITCODE -ne 0) {
      throw "psql returned exit code $LASTEXITCODE"
    }

    return @($output | Where-Object { $_ -and $_.Trim() })
  }
  finally {
    Remove-Item -LiteralPath $tempSqlPath -Force -ErrorAction SilentlyContinue
  }
}

function Get-PublishedPackageRow {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("Client", "Server")][string]$Kind,
    [Parameter(Mandatory = $true)][string]$Version
  )

  $rows = @(Invoke-PsqlRows -Sql @"
SELECT "Id", "OriginalFileName", "StoredRelativePath", "VersionLabel", "Sha256", "IsPublished", "ShowInPortal"
FROM "InstallerPackages"
WHERE "PackageType" = '$Kind'
  AND "CustomerId" IS NULL
  AND "VersionLabel" = '$Version'
ORDER BY "CreatedUtc" DESC
LIMIT 1;
"@)

  if ($rows.Count -eq 0) {
    throw "No published $Kind installer row was found for version $Version."
  }

  $parts = $rows[0].Split("|")
  return [pscustomobject]@{
    Id = $parts[0]
    OriginalFileName = $parts[1]
    StoredRelativePath = $parts[2]
    VersionLabel = $parts[3]
    Sha256 = $parts[4]
    IsPublished = $parts[5]
    ShowInPortal = $parts[6]
  }
}

function Test-PackageDownload {
  param([Parameter(Mandatory = $true)][string]$Url)

  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Head -TimeoutSec 20
    return [int]$response.StatusCode
  }
  catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      return [int]$_.Exception.Response.StatusCode
    }

    throw
  }
}

$clientRow = Get-PublishedPackageRow -Kind "Client" -Version $ClientVersion
$serverRow = Get-PublishedPackageRow -Kind "Server" -Version $ServerVersion

$results = @()
foreach ($row in @($clientRow, $serverRow)) {
  $fullPath = Join-Path $cloudRoot $row.StoredRelativePath.Replace("/", "\")
  if (-not (Test-Path -LiteralPath $fullPath)) {
    throw "Published installer file was missing on disk: $fullPath"
  }

  $fileHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
  if (-not [string]::Equals($fileHash, $row.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Published installer hash mismatch for $($row.OriginalFileName). DB=$($row.Sha256) File=$fileHash"
  }

  $downloadUrl = "{0}/Portal/Downloads" -f $CloudBaseUrl.TrimEnd("/")
  $statusCode = Test-PackageDownload -Url $downloadUrl
  if ($statusCode -lt 200 -or $statusCode -ge 400) {
    throw "Portal downloads page was not reachable at $downloadUrl (status $statusCode)."
  }

  $results += [pscustomobject]@{
    PackageType = if ($row.OriginalFileName -like "Duress.Alert.Client*") { "Client" } else { "Server" }
    Version = $row.VersionLabel
    PackageId = $row.Id
    FileName = $row.OriginalFileName
    StoredRelativePath = $row.StoredRelativePath
    Sha256 = $row.Sha256
    ShowInPortal = $row.ShowInPortal
  }
}

$results | Format-Table -AutoSize
