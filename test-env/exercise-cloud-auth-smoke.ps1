param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\cloud-auth-smoke\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$BaseUrl = "http://192.168.20.85:5186"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$devSettingsPath = Join-Path $cloudRoot "src\DuressCloud.Web\appsettings.Development.json"
$initializerPath = Join-Path $cloudRoot "src\DuressCloud.Infrastructure\Persistence\ApplicationDbInitializer.cs"
$summaryPath = Join-Path $OutputRoot "CLOUD_AUTH_SMOKE_SUMMARY.md"
$downloadPath = Join-Path $OutputRoot "portal-download-smoke.msi"
$htmlRoot = Join-Path $OutputRoot "html-snapshots"

New-Item -ItemType Directory -Force -Path $OutputRoot, $htmlRoot | Out-Null

function Get-HiddenInputValue {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $escapedName = [Regex]::Escape($Name)
  $match = [Regex]::Match($Html, "name=""$escapedName""[^>]*value=""(?<value>[^""]*)""", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $match.Success) {
    throw "Could not find hidden input '$Name'."
  }

  return [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value)
}

function Get-SharedKeyFromHtml {
  param([Parameter(Mandatory = $true)][string]$Html)

  $match = [Regex]::Match($Html, "<code>(?<key>[^<]+)</code>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $match.Success) {
    throw "Could not extract shared MFA key from the setup page."
  }

  return ([System.Net.WebUtility]::HtmlDecode($match.Groups["key"].Value) -replace "\s+", "").ToUpperInvariant()
}

function Convert-FromBase32 {
  param([Parameter(Mandatory = $true)][string]$Base32)

  $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  $clean = ($Base32 -replace "=", "" -replace "\s+", "").ToUpperInvariant()
  $bytes = New-Object System.Collections.Generic.List[byte]
  $buffer = 0
  $bitsLeft = 0

  foreach ($char in $clean.ToCharArray()) {
    $value = $alphabet.IndexOf($char)
    if ($value -lt 0) {
      throw "Base32 value contains unsupported character '$char'."
    }

    $buffer = ($buffer -shl 5) -bor $value
    $bitsLeft += 5
    while ($bitsLeft -ge 8) {
      $bitsLeft -= 8
      $bytes.Add([byte](($buffer -shr $bitsLeft) -band 0xFF))
    }
  }

  return $bytes.ToArray()
}

function Get-TotpCode {
  param([Parameter(Mandatory = $true)][string]$Base32Secret)

  $secretBytes = Convert-FromBase32 -Base32 $Base32Secret
  $counter = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30
  $counterBytes = [BitConverter]::GetBytes([Int64]$counter)
  if ([BitConverter]::IsLittleEndian) {
    [Array]::Reverse($counterBytes)
  }

  $hmac = [System.Security.Cryptography.HMACSHA1]::new($secretBytes)
  try {
    $hash = $hmac.ComputeHash($counterBytes)
  }
  finally {
    $hmac.Dispose()
  }

  $offset = $hash[$hash.Length - 1] -band 0x0F
  $binaryCode =
    (($hash[$offset] -band 0x7F) -shl 24) -bor
    (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
    (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
    ($hash[$offset + 3] -band 0xFF)

  $code = $binaryCode % 1000000
  return $code.ToString("D6")
}

function Get-AuthenticatorKeyFromDatabase {
  param(
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][string]$Email
  )

  $psqlPath = Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName |
    Select-Object -First 1 -ExpandProperty FullName

  if (-not $psqlPath) {
    throw "Could not locate psql.exe for the MFA database lookup."
  }

  $parts = @{}
  foreach ($segment in ($ConnectionString -split ';')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment.IndexOf('=') -lt 1) {
      continue
    }

    $pieces = $segment -split '=', 2
    $parts[$pieces[0].Trim()] = $pieces[1].Trim()
  }

  $dbHost = [string]$parts["Host"]
  $dbPort = [string]$parts["Port"]
  $database = [string]$parts["Database"]
  $username = [string]$parts["Username"]
  $password = [string]$parts["Password"]
  $escapedEmail = $Email.Replace("'", "''")
  $sql = @'
select ut."Value"
from "AspNetUsers" u
join "AspNetUserTokens" ut on ut."UserId" = u."Id"
where lower(u."Email") = lower('{0}')
  and ut."LoginProvider" = '[AspNetUserStore]'
  and ut."Name" = 'AuthenticatorKey'
limit 1;
'@ -f $escapedEmail

  $sqlPath = Join-Path $OutputRoot ("auth-key-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
  Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
  $previousPassword = $env:PGPASSWORD
  try {
    $env:PGPASSWORD = $password
    $output = & $psqlPath -h $dbHost -p $dbPort -U $username -d $database -t -A -f $sqlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw ("psql query failed: " + ($output | Out-String).Trim())
    }
  }
  finally {
    $env:PGPASSWORD = $previousPassword
    Remove-Item -LiteralPath $sqlPath -ErrorAction SilentlyContinue
  }

  $value = (($output | Out-String).Trim() -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "No authenticator key was found in the database for '$Email'."
  }

  return $value.Trim().ToUpperInvariant()
}

function Invoke-DatabaseScalar {
  param(
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][string]$Sql
  )

  $psqlPath = Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName |
    Select-Object -First 1 -ExpandProperty FullName

  if (-not $psqlPath) {
    throw "Could not locate psql.exe for the database lookup."
  }

  $parts = @{}
  foreach ($segment in ($ConnectionString -split ';')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment.IndexOf('=') -lt 1) {
      continue
    }

    $pieces = $segment -split '=', 2
    $parts[$pieces[0].Trim()] = $pieces[1].Trim()
  }

  $dbHost = [string]$parts["Host"]
  $dbPort = [string]$parts["Port"]
  $database = [string]$parts["Database"]
  $username = [string]$parts["Username"]
  $password = [string]$parts["Password"]
  $sqlPath = Join-Path $OutputRoot ("scalar-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
  Set-Content -Path $sqlPath -Value $Sql -Encoding UTF8
  $previousPassword = $env:PGPASSWORD
  try {
    $env:PGPASSWORD = $password
    $output = & $psqlPath -h $dbHost -p $dbPort -U $username -d $database -t -A -f $sqlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw ("psql query failed: " + ($output | Out-String).Trim())
    }
  }
  finally {
    $env:PGPASSWORD = $previousPassword
    Remove-Item -LiteralPath $sqlPath -ErrorAction SilentlyContinue
  }

  return (($output | Out-String).Trim() -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
}

function Invoke-FormGet {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  return Invoke-WebRequest -UseBasicParsing -Uri $Url -WebSession $Session -TimeoutSec 20
}

function Invoke-FormPost {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][hashtable]$Body,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  return Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded" -WebSession $Session -TimeoutSec 20
}

function Complete-MfaIfNeeded {
  param(
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [Parameter(Mandatory = $true)]$Response
  )

  $currentResponse = $Response
  $currentPath = $currentResponse.BaseResponse.ResponseUri.AbsolutePath
  while ($currentPath -match "/MfaSetup$" -or $currentPath -match "/TwoFactor$") {
    $html = [string]$currentResponse.Content
    if ($currentPath -match "/MfaSetup$") {
      $sharedKey = Get-SharedKeyFromHtml -Html $html
      $verificationToken = Get-HiddenInputValue -Html $html -Name "__RequestVerificationToken"
      $returnUrl = Get-HiddenInputValue -Html $html -Name "Input.ReturnUrl"
      $code = Get-TotpCode -Base32Secret $sharedKey
      $currentResponse = Invoke-FormPost -Url $currentResponse.BaseResponse.ResponseUri.AbsoluteUri -Session $Session -Body @{
        "__RequestVerificationToken" = $verificationToken
        "Input.VerificationCode" = $code
        "Input.ReturnUrl" = $returnUrl
      }
    }
    else {
      $sharedKey = Get-AuthenticatorKeyFromDatabase -ConnectionString $ConnectionString -Email $Email
      $verificationToken = Get-HiddenInputValue -Html $html -Name "__RequestVerificationToken"
      $returnUrl = Get-HiddenInputValue -Html $html -Name "Input.ReturnUrl"
      $code = Get-TotpCode -Base32Secret $sharedKey
      $currentResponse = Invoke-FormPost -Url $currentResponse.BaseResponse.ResponseUri.AbsoluteUri -Session $Session -Body @{
        "__RequestVerificationToken" = $verificationToken
        "Input.Code" = $code
        "Input.ReturnUrl" = $returnUrl
      }
    }

    $currentPath = $currentResponse.BaseResponse.ResponseUri.AbsolutePath
  }

  return $currentResponse
}

function Invoke-AuthenticatedLogin {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$LoginUrl,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][string]$SuccessPrefix,
    [Parameter(Mandatory = $true)][string]$ReturnUrl
  )

  $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
  $loginPage = Invoke-FormGet -Url $LoginUrl -Session $session
  $verificationToken = Get-HiddenInputValue -Html ([string]$loginPage.Content) -Name "__RequestVerificationToken"

  $loginResponse = Invoke-FormPost -Url $LoginUrl -Session $session -Body @{
    "__RequestVerificationToken" = $verificationToken
    "Input.Email" = $Email
    "Input.Password" = $Password
    "Input.ReturnUrl" = $ReturnUrl
  }

  $finalResponse = Complete-MfaIfNeeded -Email $Email -ConnectionString $ConnectionString -Session $session -Response $loginResponse
  $finalPath = $finalResponse.BaseResponse.ResponseUri.AbsolutePath
  if (-not $finalPath.StartsWith($SuccessPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name login did not land on a protected page. Final path: $finalPath"
  }

  return [pscustomobject]@{
    Session = $session
    FinalResponse = $finalResponse
    FinalPath = $finalPath
  }
}

function Assert-PagePresentation {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [Parameter(Mandatory = $true)][string[]]$ExpectedText
  )

  $response = Invoke-FormGet -Url $Url -Session $Session
  $html = [string]$response.Content
  $snapshotPath = Join-Path $htmlRoot ($Label + ".html")
  Set-Content -Path $snapshotPath -Value $html -Encoding UTF8

  foreach ($text in $ExpectedText) {
    if ($html -notmatch [Regex]::Escape($text)) {
      throw "Page presentation check failed for $Url. Missing expected text: $text"
    }
  }

  return [pscustomobject]@{
    Label = $Label
    Url = $Url
    SnapshotPath = $snapshotPath
  }
}

$devSettings = Get-Content $devSettingsPath -Raw | ConvertFrom-Json
$connectionString = [string]$devSettings.ConnectionStrings.CloudPlatform
$adminEmail = [string]$devSettings.CloudPlatform.DevelopmentAdminEmail
$adminPassword = [string]$devSettings.CloudPlatform.DevelopmentAdminPassword
$initializerContent = Get-Content $initializerPath -Raw
$portalEmailMatch = [Regex]::Match($initializerContent, 'DemoCustomerAdminEmail\s*=\s*"(?<value>[^"]+)"')
$portalPasswordMatch = [Regex]::Match($initializerContent, 'DemoCustomerAdminPassword\s*=\s*"(?<value>[^"]+)"')
if (-not $portalEmailMatch.Success -or -not $portalPasswordMatch.Success) {
  throw "Could not read demo portal credentials from ApplicationDbInitializer.cs."
}

$portalEmail = $portalEmailMatch.Groups["value"].Value
$portalPassword = $portalPasswordMatch.Groups["value"].Value
$escapedPortalEmail = $portalEmail.Replace("'", "''")
$portalCustomerSql = @'
select u."CustomerId"::text
from "AspNetUsers" u
where lower(u."Email") = lower('{0}')
limit 1;
'@ -f $escapedPortalEmail
$portalCustomerId = Invoke-DatabaseScalar -ConnectionString $connectionString -Sql $portalCustomerSql
if ([string]::IsNullOrWhiteSpace($portalCustomerId)) {
  throw "Could not resolve the seeded portal customer's id from the database."
}

$base = $BaseUrl.TrimEnd('/')
$managementLoginUrl = "$base/Management/Login"
$portalLoginUrl = "$base/Portal/Login"
$managementInstallersUrl = "$base/Management/Installers"
$portalDownloadsUrl = "$base/Portal/Downloads"

$managementAuth = Invoke-AuthenticatedLogin -Name "Management" -LoginUrl $managementLoginUrl -Email $adminEmail -Password $adminPassword -ConnectionString $connectionString -SuccessPrefix "/Management" -ReturnUrl "/Management/Installers"
$managementInstallers = Invoke-FormGet -Url $managementInstallersUrl -Session $managementAuth.Session
if ($managementInstallers.BaseResponse.ResponseUri.AbsolutePath -notlike "/Management/Installers*") {
  throw "Authenticated management session did not reach /Management/Installers."
}

$managementHtml = [string]$managementInstallers.Content
Set-Content -Path (Join-Path $htmlRoot "management-installers.html") -Value $managementHtml -Encoding UTF8
if ($managementHtml -notmatch "Client terminal-services guide") {
  throw "Management installers page did not show the terminal-services guide."
}

if ($managementHtml -notmatch "\.msi") {
  throw "Management installers page did not show any MSI package references."
}

$managementChecks = @(
  @{ Label = "management-users"; Url = "$base/Management/Users"; Expected = @("INTERNAL AND EXTERNAL USERS", "Back to management", "Create staff user") },
  @{ Label = "management-operations"; Url = "$base/Management/Operations"; Expected = @("Operations", "Operational queue", "Recent automation") },
  @{ Label = "admin-customers"; Url = "$base/Admin/Customers"; Expected = @("Customers", "Status", "Create customer") },
  @{ Label = "admin-customer-details"; Url = "$base/Admin/Customers/Details/$portalCustomerId"; Expected = @("CUSTOMER DETAIL", "Subscriptions", "Payment requests") }
)

$pageSnapshots = New-Object System.Collections.Generic.List[object]
foreach ($check in $managementChecks) {
  $pageSnapshots.Add((Assert-PagePresentation -Label $check.Label -Url $check.Url -Session $managementAuth.Session -ExpectedText $check.Expected))
}

$portalAuth = Invoke-AuthenticatedLogin -Name "Portal" -LoginUrl $portalLoginUrl -Email $portalEmail -Password $portalPassword -ConnectionString $connectionString -SuccessPrefix "/Portal" -ReturnUrl "/Portal/Downloads"
$portalDownloads = Invoke-FormGet -Url $portalDownloadsUrl -Session $portalAuth.Session
if ($portalDownloads.BaseResponse.ResponseUri.AbsolutePath -notlike "/Portal/Downloads*") {
  throw "Authenticated portal session did not reach /Portal/Downloads."
}

$portalHtml = [string]$portalDownloads.Content
Set-Content -Path (Join-Path $OutputRoot "portal-downloads.html") -Value $portalHtml -Encoding UTF8
Set-Content -Path (Join-Path $htmlRoot "portal-downloads.html") -Value $portalHtml -Encoding UTF8
if ($portalHtml -notmatch "Download the current Duress Alert software") {
  throw "Portal downloads page did not render the expected downloads content."
}

$downloadMatch = [Regex]::Match($portalHtml, 'href="(?<href>[^"]*Downloads[^"]*id=[^"]*handler=Download[^"]*)"|href="(?<href_alt>[^"]*Downloads[^"]*handler=Download[^"]*id=[^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $downloadMatch.Success) {
  throw "Portal downloads page did not expose any installer download links."
}

$downloadHref = if ($downloadMatch.Groups["href"].Success) { $downloadMatch.Groups["href"].Value } else { $downloadMatch.Groups["href_alt"].Value }
$downloadHref = [System.Net.WebUtility]::HtmlDecode($downloadHref)
$downloadUrl = if ($downloadHref.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) { $downloadHref } else { "$base$downloadHref" }
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -WebSession $portalAuth.Session -OutFile $downloadPath -TimeoutSec 60

if (-not (Test-Path $downloadPath)) {
  throw "Portal installer download did not produce a file."
}

$downloadFile = Get-Item $downloadPath
if ($downloadFile.Length -le 0) {
  throw "Portal installer download produced an empty file."
}

$portalChecks = @(
  @{ Label = "portal-subscriptions"; Url = "$base/Portal/Subscriptions"; Expected = @("Subscriptions", "Status", "Renewal") },
  @{ Label = "portal-payments"; Url = "$base/Portal/Payments"; Expected = @("Payments", "Status", "Amount") },
  @{ Label = "portal-trial"; Url = "$base/Portal/Trial"; Expected = @("Trial", "trial", "request") }
)

foreach ($check in $portalChecks) {
  $pageSnapshots.Add((Assert-PagePresentation -Label $check.Label -Url $check.Url -Session $portalAuth.Session -ExpectedText $check.Expected))
}

$summary = @()
$summary += "# Cloud Auth Smoke"
$summary += ""
$summary += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summary += ""
$summary += "## Coverage"
$summary += ""
$summary += "- Staff login with MFA completion when required"
$summary += "- Management installers page access"
$summary += "- Management users, operations, and admin customer detail access"
$summary += "- Installer guide presence and MSI catalog visibility"
$summary += "- Portal login with MFA completion when required"
$summary += "- Portal downloads page access"
$summary += "- Portal subscriptions, payments, and trial access"
$summary += "- HTML page snapshots for key authenticated pages"
$summary += "- Real MSI download from the portal"
$summary += ""
$summary += "## Results"
$summary += ""
$summary += "- Management final path: $($managementAuth.FinalPath)"
$summary += "- Portal final path: $($portalAuth.FinalPath)"
$summary += "- Downloaded installer: [$($downloadFile.Name)]($($downloadFile.FullName -replace '\\','/')) ($($downloadFile.Length) bytes)"
$summary += "- Page snapshots:"
foreach ($snapshot in $pageSnapshots) {
  $summary += "  - [$($snapshot.Label)]($($snapshot.SnapshotPath -replace '\\','/'))"
}

Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

Write-Host "Cloud auth smoke written to: $OutputRoot"
Write-Host "Summary: $summaryPath"
