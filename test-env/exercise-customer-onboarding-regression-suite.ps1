param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot ("sandbox\\customer-onboarding\\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
  [string]$BaseUrl = "http://192.168.20.85:5186"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "_workspace-root.ps1")
$workspaceRoot = Get-DuressWorkspaceRoot -ScriptRoot $scriptRoot
$cloudRoot = Join-Path $workspaceRoot "DuressCloud"
$devSettingsPath = Join-Path $cloudRoot "src\DuressCloud.Web\appsettings.Development.json"
$logsRoot = Join-Path $OutputRoot "logs"
$summaryPath = Join-Path $OutputRoot "CUSTOMER_ONBOARDING_REGRESSION_SUMMARY.md"

New-Item -ItemType Directory -Force -Path $OutputRoot, $logsRoot | Out-Null

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

function Get-FirstInputValue {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $escapedName = [Regex]::Escape($Name)
  $match = [Regex]::Match($Html, "name=""$escapedName""[^>]*value=""(?<value>[^""]*)""", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $match.Success) {
    throw "Could not find input '$Name'."
  }

  return [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value)
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

  return ($binaryCode % 1000000).ToString("D6")
}

function Get-ConnectionString {
  $settings = Get-Content -Path $devSettingsPath -Raw | ConvertFrom-Json
  $connectionString = [string]$settings.ConnectionStrings.CloudPlatform
  if ([string]::IsNullOrWhiteSpace($connectionString)) {
    throw "Could not find CloudPlatform connection string in $devSettingsPath."
  }

  return $connectionString
}

function Get-PsqlPath {
  $psqlPath = Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName |
    Select-Object -First 1 -ExpandProperty FullName

  if (-not $psqlPath) {
    throw "Could not locate psql.exe for the database lookup."
  }

  return $psqlPath
}

function Invoke-DatabaseScalar {
  param(
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][string]$Sql
  )

  $psqlPath = Get-PsqlPath
  $parts = @{}
  foreach ($segment in ($ConnectionString -split ';')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment.IndexOf('=') -lt 1) {
      continue
    }

    $pieces = $segment -split '=', 2
    $parts[$pieces[0].Trim()] = $pieces[1].Trim()
  }

  $sqlPath = Join-Path $OutputRoot ("scalar-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
  Set-Content -Path $sqlPath -Value $Sql -Encoding UTF8
  $previousPassword = $env:PGPASSWORD
  try {
    $env:PGPASSWORD = [string]$parts["Password"]
    $output = & $psqlPath -h ([string]$parts["Host"]) -p ([string]$parts["Port"]) -U ([string]$parts["Username"]) -d ([string]$parts["Database"]) -t -A -f $sqlPath 2>&1
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

  return Invoke-WebRequest -UseBasicParsing -Uri $Url -WebSession $Session -TimeoutSec 30
}

function Invoke-FormPost {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][hashtable]$Body,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  return Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded" -WebSession $Session -TimeoutSec 30
}

function Complete-MfaIfNeeded {
  param(
    [Parameter(Mandatory = $true)][string]$ConnectionString,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [Parameter(Mandatory = $true)]$Response
  )

  $currentResponse = $Response
  while ($currentResponse.BaseResponse.ResponseUri.AbsolutePath -match "/MfaSetup$" -or $currentResponse.BaseResponse.ResponseUri.AbsolutePath -match "/TwoFactor$") {
    $html = [string]$currentResponse.Content
    if ($currentResponse.BaseResponse.ResponseUri.AbsolutePath -match "/MfaSetup$") {
      $sharedKey = [Regex]::Match($html, "<code>(?<key>[^<]+)</code>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Groups["key"].Value
      if ([string]::IsNullOrWhiteSpace($sharedKey)) {
        throw "Could not extract MFA setup key."
      }

      $currentResponse = Invoke-FormPost -Url $currentResponse.BaseResponse.ResponseUri.AbsoluteUri -Session $Session -Body @{
        "__RequestVerificationToken" = Get-HiddenInputValue -Html $html -Name "__RequestVerificationToken"
        "Input.ReturnUrl" = Get-HiddenInputValue -Html $html -Name "Input.ReturnUrl"
        "Input.VerificationCode" = Get-TotpCode -Base32Secret (($sharedKey -replace "\s+", "").ToUpperInvariant())
      }
    }
    else {
      $escapedEmail = $Email.Replace("'", "''")
      $authKey = Invoke-DatabaseScalar -ConnectionString $ConnectionString -Sql @"
select ut."Value"
from "AspNetUsers" u
join "AspNetUserTokens" ut on ut."UserId" = u."Id"
where lower(u."Email") = lower('$escapedEmail')
  and ut."LoginProvider" = '[AspNetUserStore]'
  and ut."Name" = 'AuthenticatorKey'
limit 1;
"@
      if ([string]::IsNullOrWhiteSpace($authKey)) {
        throw "Could not locate authenticator key for $Email."
      }

      $currentResponse = Invoke-FormPost -Url $currentResponse.BaseResponse.ResponseUri.AbsoluteUri -Session $Session -Body @{
        "__RequestVerificationToken" = Get-HiddenInputValue -Html $html -Name "__RequestVerificationToken"
        "Input.ReturnUrl" = Get-HiddenInputValue -Html $html -Name "Input.ReturnUrl"
        "Input.Code" = Get-TotpCode -Base32Secret $authKey
      }
    }
  }

  return $currentResponse
}

function New-CustomerJourneyIdentity {
  param([Parameter(Mandatory = $true)][string]$Scenario)

  $stamp = Get-Date -Format "yyyyMMddHHmmssfff"
  $safeScenario = ($Scenario -replace "[^a-zA-Z0-9]", "").ToLowerInvariant()
  $domain = "$safeScenario-$stamp.duress-e2e.com"
  return [pscustomobject]@{
    OrganisationName = "Duress E2E $Scenario $stamp"
    FirstAdminName = "Automation $Scenario"
    FirstAdminEmail = "admin@$domain"
    BillingEmail = "billing@$domain"
    Password = "Duress!${stamp}Aa"
    Phone = "1300366911"
    BillingAbn = ""
    BillingEntityName = "Duress E2E $Scenario $stamp"
    AddressLine1 = "99 Queen Street"
    AddressLine2 = "Suite 8"
    Suburb = "Melbourne"
    State = "VIC"
    Postcode = "3000"
    Country = "Australia"
  }
}

function Invoke-SignupAndPortalBootstrap {
  param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$ConnectionString
  )

  $identity = New-CustomerJourneyIdentity -Scenario $Scenario
  $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

  $signupGet = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Signup") -Session $session
  $signupHtml = [string]$signupGet.Content
  $signupPost = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Signup") -Session $session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $signupHtml -Name "__RequestVerificationToken"
    "Input.OrganisationName" = $identity.OrganisationName
    "Input.BillingEntityName" = $identity.BillingEntityName
    "Input.BillingEntitySameAsOrganisation" = "true"
    "Input.FirstAdminName" = $identity.FirstAdminName
    "Input.FirstAdminEmail" = $identity.FirstAdminEmail
    "Input.BillingEmail" = $identity.BillingEmail
    "Input.Phone" = $identity.Phone
    "Input.BillingAbn" = $identity.BillingAbn
    "Input.OrganisationAddressLine1" = $identity.AddressLine1
    "Input.OrganisationAddressLine2" = $identity.AddressLine2
    "Input.OrganisationSuburb" = $identity.Suburb
    "Input.OrganisationState" = $identity.State
    "Input.OrganisationPostcode" = $identity.Postcode
    "Input.OrganisationCountry" = $identity.Country
    "Input.BillingAddressSameAsOrganisation" = "true"
    "Input.BillingAddressLine1" = $identity.AddressLine1
    "Input.BillingAddressLine2" = $identity.AddressLine2
    "Input.BillingSuburb" = $identity.Suburb
    "Input.BillingState" = $identity.State
    "Input.BillingPostcode" = $identity.Postcode
    "Input.BillingCountry" = $identity.Country
  }

  $signupResponseHtml = [string]$signupPost.Content
  if ($signupResponseHtml -notmatch "Successfully created" -or $signupResponseHtml -notmatch "Please check your email") {
    throw "Signup did not reach the expected success state for scenario '$Scenario'."
  }

  $escapedEmail = $identity.FirstAdminEmail.Replace("'", "''")
  $inviteId = Invoke-DatabaseScalar -ConnectionString $ConnectionString -Sql @"
select "Id"
from "PortalInviteLinks"
where lower("Email") = lower('$escapedEmail')
order by "CreatedUtc" desc
limit 1;
"@
  if ([string]::IsNullOrWhiteSpace($inviteId)) {
    throw "Could not locate portal invite for $($identity.FirstAdminEmail)."
  }

  $customerId = Invoke-DatabaseScalar -ConnectionString $ConnectionString -Sql @"
select "Id"
from "Customers"
where lower("PrimaryContactEmail") = lower('$escapedEmail')
order by "CreatedUtc" desc
limit 1;
"@
  if ([string]::IsNullOrWhiteSpace($customerId)) {
    throw "Could not locate created customer for $($identity.FirstAdminEmail)."
  }

  $inviteResponse = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Portal/ResetPassword?invite=$inviteId") -Session $session
  $inviteHtml = [string]$inviteResponse.Content
  $resetResponse = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Portal/ResetPassword?invite=$inviteId") -Session $session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $inviteHtml -Name "__RequestVerificationToken"
    "Input.Email" = Get-HiddenInputValue -Html $inviteHtml -Name "Input.Email"
    "Input.Token" = Get-HiddenInputValue -Html $inviteHtml -Name "Input.Token"
    "Input.InviteId" = Get-HiddenInputValue -Html $inviteHtml -Name "Input.InviteId"
    "Input.NewPassword" = $identity.Password
    "Input.ConfirmPassword" = $identity.Password
  }

  $portalResponse = Complete-MfaIfNeeded -ConnectionString $ConnectionString -Email $identity.FirstAdminEmail -Session $session -Response $resetResponse
  if ($portalResponse.BaseResponse.ResponseUri.AbsolutePath -notmatch "/Portal/Index$") {
    throw "Portal bootstrap did not land on /Portal/Index for scenario '$Scenario'. Final URL: $($portalResponse.BaseResponse.ResponseUri.AbsoluteUri)"
  }

  return [pscustomobject]@{
    Scenario = $Scenario
    Identity = $identity
    Session = $session
    CustomerId = $customerId
    PortalResponse = $portalResponse
  }
}

function Assert-RedirectedAwayFromDownloads {
  param(
    [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  $downloadsResponse = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Portal/Downloads") -Session $Session
  if ($downloadsResponse.BaseResponse.ResponseUri.AbsolutePath -notmatch "^/Portal(?:/Index)?$") {
    throw "Downloads were accessible too early for scenario '$Scenario'. Final URL: $($downloadsResponse.BaseResponse.ResponseUri.AbsoluteUri)"
  }
}

function Invoke-TrialJourney {
  param(
    [Parameter(Mandatory = $true)]$Journey,
    [Parameter(Mandatory = $true)][string]$ConnectionString
  )

  Assert-RedirectedAwayFromDownloads -Session $Journey.Session -Scenario $Journey.Scenario

  $trialGet = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Portal/Trial/Index") -Session $Journey.Session
  $trialHtml = [string]$trialGet.Content
  $acceptTerms = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Portal/Trial/Index?handler=AcceptCurrentTerms") -Session $Journey.Session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $trialHtml -Name "__RequestVerificationToken"
    "TermsInput.AcceptProductTerms" = "true"
    "TermsInput.AcceptTrialConditions" = "true"
  }

  $acceptedHtml = [string]$acceptTerms.Content
  if ($acceptedHtml -notmatch "Current product and trial terms have been accepted" -and $acceptedHtml -notmatch "Current version already accepted") {
    throw "Trial terms acceptance did not complete for scenario '$($Journey.Scenario)'."
  }

  $trialStart = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Portal/Trial/Index?handler=StartSelfServiceTrial") -Session $Journey.Session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $acceptedHtml -Name "__RequestVerificationToken"
  }

  $trialStartHtml = [string]$trialStart.Content
  if ($trialStartHtml -notmatch "Your claim token is ready") {
    throw "Self-service trial did not expose the claim token for scenario '$($Journey.Scenario)'."
  }

  $trialEndUtcRaw = Invoke-DatabaseScalar -ConnectionString $ConnectionString -Sql @"
select "TrialEndUtc"
from "Customers"
where "Id" = '$($Journey.CustomerId)'
limit 1;
"@
  if ([string]::IsNullOrWhiteSpace($trialEndUtcRaw)) {
    throw "Could not read trial end date for scenario '$($Journey.Scenario)'."
  }

  $trialEndUtc = [DateTimeOffset]::Parse($trialEndUtcRaw)
  $trialDays = [Math]::Round(($trialEndUtc - [DateTimeOffset]::UtcNow).TotalDays)
  if ($trialDays -lt 20 -or $trialDays -gt 22) {
    throw "Expected approximately 21 trial days after self-service activation but found $trialDays."
  }

  $downloadsResponse = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Portal/Downloads") -Session $Journey.Session
  if ($downloadsResponse.BaseResponse.ResponseUri.AbsolutePath -notmatch "/Portal/Downloads$") {
    throw "Downloads did not unlock after self-service trial for scenario '$($Journey.Scenario)'."
  }

  if ([string]$downloadsResponse.Content -notmatch "Download") {
    throw "Downloads page did not render installer actions after trial unlock."
  }

  return [pscustomobject]@{
    Scenario = $Journey.Scenario
    TrialDays = $trialDays
    DownloadsUnlocked = $true
  }
}

function Invoke-PurchaseJourney {
  param(
    [Parameter(Mandatory = $true)]$Journey,
    [Parameter(Mandatory = $true)][string]$ConnectionString
  )

  Assert-RedirectedAwayFromDownloads -Session $Journey.Session -Scenario $Journey.Scenario

  $purchaseGet = Invoke-FormGet -Url ($BaseUrl.TrimEnd('/') + "/Portal/Purchase/Index") -Session $Journey.Session
  $purchaseHtml = [string]$purchaseGet.Content
  $acceptTerms = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Portal/Purchase/Index?handler=AcceptCurrentTerms") -Session $Journey.Session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $purchaseHtml -Name "__RequestVerificationToken"
    "TermsInput.AcceptProductTerms" = "true"
  }

  $acceptedHtml = [string]$acceptTerms.Content
  $productSelection = Invoke-DatabaseScalar -ConnectionString $ConnectionString -Sql @"
select concat("Id"::text, '|', "MinSeats"::text, '|', coalesce("MaxSeats"::text, ''), '|', "Type"::text)
from "ProductCatalogItems"
where "IsActive" = true
  and "IsPublic" = true
  and "SelfServiceEnabled" = true
  and "RequiresQuote" = false
order by "DisplayOrder", "Name"
limit 1;
"@
  if ([string]::IsNullOrWhiteSpace($productSelection)) {
    throw "Could not locate a self-service product for the purchase journey."
  }

  $selectionParts = $productSelection.Split('|')
  $productId = $selectionParts[0]
  $seatCount = $selectionParts[1]
  $productType = if ($selectionParts.Length -ge 4) { $selectionParts[3] } else { "0" }
  $siteCount = if ($productType -eq "1") { "0" } else { "1" }

  $purchasePost = Invoke-FormPost -Url ($BaseUrl.TrimEnd('/') + "/Portal/Purchase/Index?handler=CreatePayment") -Session $Journey.Session -Body @{
    "__RequestVerificationToken" = Get-HiddenInputValue -Html $acceptedHtml -Name "__RequestVerificationToken"
    "Input.ProductCatalogItemId" = $productId
    "Input.SeatCount" = $seatCount
    "Input.SiteCount" = $siteCount
  }

  if ($purchasePost.BaseResponse.ResponseUri.AbsolutePath -notmatch "/Portal/Payments/Details/") {
    throw "Purchase flow did not land on a payment details page for scenario '$($Journey.Scenario)'. Final URL: $($purchasePost.BaseResponse.ResponseUri.AbsoluteUri)"
  }

  $paymentHtml = [string]$purchasePost.Content
  if ($paymentHtml -notmatch "Payment details") {
    throw "Purchase flow did not render the payment details page."
  }

  if ($paymentHtml -notmatch "Pending") {
    throw "Customer purchase flow did not show the customer-facing Pending status."
  }

  if ($paymentHtml -notmatch "Open payment page") {
    throw "Customer purchase flow did not provide the payment page action."
  }

  return [pscustomobject]@{
    Scenario = $Journey.Scenario
    PaymentDetailsPath = $purchasePost.BaseResponse.ResponseUri.AbsolutePath
    Status = "Pending"
  }
}

function Invoke-And-Capture {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  $logPath = Join-Path $logsRoot ($Name + ".log")
  Write-Host "Running:" $Name
  try {
    $output = & $Action 2>&1 | Tee-Object -FilePath $logPath
    return [pscustomobject]@{
      Name = $Name
      Success = $true
      LogPath = $logPath
      Output = ($output | Out-String)
    }
  }
  catch {
    $_ | Out-String | Tee-Object -FilePath $logPath -Append | Out-Null
    return [pscustomobject]@{
      Name = $Name
      Success = $false
      LogPath = $logPath
      Output = (Get-Content $logPath -Raw)
    }
  }
}

$connectionString = Get-ConnectionString
$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-And-Capture -Name "01-signup-legal-trial-downloads" -Action {
  $journey = Invoke-SignupAndPortalBootstrap -Scenario "Trial" -ConnectionString $connectionString
  Invoke-TrialJourney -Journey $journey -ConnectionString $connectionString | Format-List
}))

$results.Add((Invoke-And-Capture -Name "02-signup-legal-purchase-payment" -Action {
  $journey = Invoke-SignupAndPortalBootstrap -Scenario "Purchase" -ConnectionString $connectionString
  Invoke-PurchaseJourney -Journey $journey -ConnectionString $connectionString | Format-List
}))

$lines = @()
$lines += "# Customer Onboarding Regression Suite"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "## Coverage"
$lines += ""
$lines += "- Public signup creates a new organisation and first portal admin"
$lines += "- Invite-based password setup and MFA enrolment completes successfully"
$lines += "- Downloads stay locked before entitlement"
$lines += "- Trial terms acceptance unlocks self-service trial and downloads"
$lines += "- Product terms acceptance unlocks self-service purchase creation"
$lines += "- Customer purchase lands on a pending payment page with a checkout action"
$lines += ""
$lines += "## Results"
$lines += ""
foreach ($result in $results) {
  $status = if ($result.Success) { "PASS" } else { "FAIL" }
  $lines += "- $status [$($result.Name)]($($result.LogPath -replace '\\','/'))"
}
$lines += ""
$lines += "## Notes"
$lines += ""
$lines += "- This suite uses two fresh customer identities so the trial and purchase journeys do not interfere with each other."
$lines += "- It uses the same invite, MFA, legal-acceptance, trial, purchase, and download paths that real customer admins use in the portal."

Set-Content -Path $summaryPath -Value $lines -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
Write-Host "Customer onboarding regression suite written to: $OutputRoot"
Write-Host "Summary: $summaryPath"

if ($failed.Count -gt 0) {
  throw ("Customer onboarding regression suite completed with failures: " + (($failed | ForEach-Object { $_.Name }) -join ", "))
}
