param(
    [string]$BaseUrl = 'http://localhost:5186',
    [string]$DatabaseName = 'duress_cloud_dev',
    [string]$DatabaseUser = 'duress_app',
    [string]$DatabasePassword = 'DuressCloudLocal!2026',
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'
)

$ErrorActionPreference = 'Stop'

$cloudRoot = 'C:\OLDD\Duress\DuressCloud'
$env:PGPASSWORD = $DatabasePassword
$sqlPath = $null
$verifyPath = $null
$process = $null

try {
    $sql = @"
update "IntegrationSettings"
set "PublicApiEnabled" = true,
    "PublicApiKey" = 'dev-public-key',
    "WooCommerceWebhookSecret" = 'dev-woo-secret'
where "Id" in (select "Id" from "IntegrationSettings" limit 1);
"@

    $sqlPath = Join-Path $env:TEMP ('duress-public-api-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $sqlPath -Value $sql -Encoding UTF8
    & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $sqlPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to enable public integration settings.'
    }

    $process = Start-Process -FilePath 'C:\Program Files\dotnet\dotnet.exe' `
        -ArgumentList 'run --project .\src\DuressCloud.Web\DuressCloud.Web.csproj -- --urls http://localhost:5186' `
        -WorkingDirectory $cloudRoot `
        -PassThru `
        -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        try {
            if ((Invoke-WebRequest -UseBasicParsing "$BaseUrl/ready" -TimeoutSec 5).StatusCode -eq 200) {
                $ready = $true
                break
            }
        }
        catch {
        }
    }

    if (-not $ready) {
        throw "Cloud app did not become ready at '$BaseUrl'."
    }

    $headers = @{ 'X-Duress-Integration-Key' = 'dev-public-key' }

    $customerBody = @{
        CustomerName = 'Replay Test Clinic'
        PrimaryContactName = 'Jane Admin'
        PrimaryContactEmail = 'jane@example.com'
        BillingEntityName = 'Replay Billing Pty Ltd'
        BillingEmail = 'billing@example.com'
        BillingAbn = '12345678901'
        ClinicAddress = '1 Example St'
        Phone = '1300 000 000'
        ItContactName = 'IT Manager'
        ItContactPhone = '0400 000 001'
        ItContactEmail = 'it@example.com'
        SourceSystem = 'wordpress'
        ExternalReference = 'wp-customer-1001'
    } | ConvertTo-Json

    $customer1 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/public/customer-upsert" -Headers $headers -ContentType 'application/json' -Body $customerBody
    $customer2 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/public/customer-upsert" -Headers $headers -ContentType 'application/json' -Body $customerBody

    $paymentBody = @{
        CustomerName = 'Replay Test Clinic'
        CustomerEmail = 'jane@example.com'
        Description = 'Annual Duress Renewal'
        AmountAud = 299.00
        SystemName = 'Reception Server'
        ExpiryDays = 14
        SourceSystem = 'wordpress'
        ExternalReference = 'wp-payment-2001'
    } | ConvertTo-Json

    $payment1 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/public/payment-request" -Headers $headers -ContentType 'application/json' -Body $paymentBody
    $payment2 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/public/payment-request" -Headers $headers -ContentType 'application/json' -Body $paymentBody

    $wooPayload = @{
        number = 'WC-9001'
        description = 'Woo Annual Renewal'
        total = '499.00'
        billing = @{
            first_name = 'Casey'
            last_name = 'Clinic'
            email = 'casey@example.com'
            company = 'Woo Replay Clinic'
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes('dev-woo-secret'))
    try {
        $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($wooPayload)))
    }
    finally {
        $hmac.Dispose()
    }

    $wooHeaders = @{ 'X-WC-Webhook-Signature' = $signature }
    $woo1 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/woocommerce/order-paid" -Headers $wooHeaders -ContentType 'application/json' -Body $wooPayload
    $woo2 = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/integrations/woocommerce/order-paid" -Headers $wooHeaders -ContentType 'application/json' -Body $wooPayload

    $verifySql = @"
select count(*) from "Customers" where "ExternalSourceSystem" = 'wordpress' and "ExternalReference" = 'wp-customer-1001';
select count(*) from "PaymentRequests" where "ExternalSourceSystem" = 'wordpress' and "ExternalReference" = 'wp-payment-2001';
select count(*) from "PaymentRequests" where "ExternalSourceSystem" = 'woocommerce' and "ExternalReference" = 'order:WC-9001';
"@

    $verifyPath = Join-Path $env:TEMP ('duress-public-api-verify-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $verifyPath -Value $verifySql -Encoding UTF8
    $counts = & $PsqlPath -h localhost -U $DatabaseUser -d $DatabaseName -t -A -f $verifyPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to verify replay counts.'
    }

    Write-Host ('Customer1Id=' + $customer1.customerId)
    Write-Host ('Customer2Id=' + $customer2.customerId)
    Write-Host ('Payment1Id=' + $payment1.paymentRequestId)
    Write-Host ('Payment2Id=' + $payment2.paymentRequestId)
    Write-Host ('Payment2Existing=' + $payment2.existing)
    Write-Host ('Woo1Id=' + $woo1.paymentRequestId)
    Write-Host ('Woo2Id=' + $woo2.paymentRequestId)
    Write-Host ('Woo2Existing=' + $woo2.existing)
    Write-Host 'Counts:'
    $counts | ForEach-Object { Write-Host $_ }
}
finally {
    if ($sqlPath -and (Test-Path $sqlPath)) {
        Remove-Item $sqlPath -Force -ErrorAction SilentlyContinue
    }

    if ($verifyPath -and (Test-Path $verifyPath)) {
        Remove-Item $verifyPath -Force -ErrorAction SilentlyContinue
    }

    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
