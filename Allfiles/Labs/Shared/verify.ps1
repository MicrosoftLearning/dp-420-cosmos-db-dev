<#
.SYNOPSIS
    Verifies that a lab account is correctly provisioned for a DP-420 exercise.

.DESCRIPTION
    Checks the account configuration, the containers a lab profile expects, the
    data-plane role assignment, and an authenticated read against seeded data.

    The final check uses the same Microsoft Entra ID token path that setup.ps1
    uses to write items, so it confirms authentication end to end.

.EXAMPLE
    ./verify.ps1 -ResourceGroup dp420 -AccountName dp420-cosmos-abc123
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$AccountName,

    [ValidateSet('core', 'modeling')]
    [string]$LabProfile = 'core'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Failures = 0

function Test-Condition {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )

    if ($Passed) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
        $script:Failures++
    }
}

Write-Host "Verifying '$AccountName' for the $LabProfile lab profile." -ForegroundColor Cyan
Write-Host ''

Write-Host 'Account' -ForegroundColor Cyan
$account = & az cosmosdb show --name $AccountName --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json

if (-not $account) {
    Write-Host "  FAIL  Account not found in resource group '$ResourceGroup'." -ForegroundColor Red
    exit 1
}

Test-Condition -Name 'Account exists' -Passed $true
Test-Condition -Name 'Key-based authentication disabled' -Passed ($account.disableLocalAuth -eq $true) `
    -Detail 'Expected disableLocalAuth = true. Re-run setup.ps1 or set it with az cosmosdb update --disable-local-auth true.'
Test-Condition -Name 'API is NoSQL' -Passed ($account.kind -eq 'GlobalDocumentDB')

$endpoint = $account.documentEndpoint
Write-Host "        Endpoint: $endpoint" -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Role assignment' -ForegroundColor Cyan
$principalId = (& az ad signed-in-user show --query id --output tsv).Trim()
$assignments = & az cosmosdb sql role assignment list --account-name $AccountName --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json
$hasContributor = @($assignments | Where-Object {
        $_.principalId -eq $principalId -and $_.roleDefinitionId -match '0000000000000000000000000000000000000002|00000000-0000-0000-0000-000000000002'
    }).Count -gt 0

Test-Condition -Name 'Signed-in user holds Built-in Data Contributor' -Passed $hasContributor `
    -Detail 'Without this role every data operation returns 403.'

Write-Host ''
Write-Host 'Containers' -ForegroundColor Cyan

$expected = if ($LabProfile -eq 'core') {
    @(
        @{ Database = 'cosmicworks'; Name = 'product';     PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
        @{ Database = 'cosmicworks'; Name = 'productMeta'; PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 237 }
        @{ Database = 'cosmicworks'; Name = 'leases';      PartitionKey = '/id' }
        @{ Database = 'cosmicworks'; Name = 'operations';  PartitionKey = '/categoryId' }
        @{ Database = 'cosmicworks'; Name = 'bulkload';    PartitionKey = '/categoryId' }
    )
}
else {
    @(
        @{ Database = 'database-v1'; Name = 'customer';         PartitionKey = '/id';         MinItems = 10 }
        @{ Database = 'database-v1'; Name = 'customerAddress';  PartitionKey = '/id';         MinItems = 10 }
        @{ Database = 'database-v1'; Name = 'customerPassword'; PartitionKey = '/id';         MinItems = 10 }
        @{ Database = 'database-v1'; Name = 'product';          PartitionKey = '/id';         MinItems = 295 }
        @{ Database = 'database-v1'; Name = 'productCategory';  PartitionKey = '/id';         MinItems = 37 }
        @{ Database = 'database-v1'; Name = 'productTag';       PartitionKey = '/id';         MinItems = 200 }
        @{ Database = 'database-v1'; Name = 'productTags';      PartitionKey = '/id';         MinItems = 767 }
        @{ Database = 'database-v1'; Name = 'salesOrder';       PartitionKey = '/id';         MinItems = 272 }
        @{ Database = 'database-v1'; Name = 'salesOrderDetail'; PartitionKey = '/id';         MinItems = 610 }

        @{ Database = 'database-v2'; Name = 'customer';         PartitionKey = '/id';         MinItems = 10 }
        @{ Database = 'database-v2'; Name = 'product';          PartitionKey = '/categoryId'; MinItems = 295 }
        @{ Database = 'database-v2'; Name = 'productCategory';  PartitionKey = '/type';       MinItems = 37 }
        @{ Database = 'database-v2'; Name = 'productTag';       PartitionKey = '/type';       MinItems = 200 }
        @{ Database = 'database-v2'; Name = 'salesOrder';       PartitionKey = '/customerId'; MinItems = 272 }

        @{ Database = 'database-v3'; Name = 'customer';         PartitionKey = '/id';         MinItems = 10 }
        @{ Database = 'database-v3'; Name = 'product';          PartitionKey = '/categoryId'; MinItems = 295 }
        @{ Database = 'database-v3'; Name = 'productCategory';  PartitionKey = '/type';       MinItems = 37 }
        @{ Database = 'database-v3'; Name = 'productTag';       PartitionKey = '/type';       MinItems = 200 }
        @{ Database = 'database-v3'; Name = 'salesOrder';       PartitionKey = '/customerId'; MinItems = 272 }

        @{ Database = 'database-v4'; Name = 'customer';         PartitionKey = '/customerId'; MinItems = 282 }
        @{ Database = 'database-v4'; Name = 'product';          PartitionKey = '/categoryId'; MinItems = 295 }
        @{ Database = 'database-v4'; Name = 'productMeta';      PartitionKey = '/type';       MinItems = 237 }
    )
}

foreach ($item in $expected) {
    if (-not $item.Name) {
        $exists = (& az cosmosdb sql database exists --account-name $AccountName --resource-group $ResourceGroup --name $item.Database --output tsv 2>$null)
        Test-Condition -Name "Database $($item.Database)" -Passed ($exists -eq 'true')
        continue
    }

    $container = & az cosmosdb sql container show `
        --account-name $AccountName --resource-group $ResourceGroup `
        --database-name $item.Database --name $item.Name --output json 2>$null | ConvertFrom-Json

    if (-not $container) {
        Test-Condition -Name "Container $($item.Database)/$($item.Name)" -Passed $false -Detail 'Not found.'
        continue
    }

    $actualKey = $container.resource.partitionKey.paths[0]
    Test-Condition -Name "Container $($item.Database)/$($item.Name) on $($item.PartitionKey)" `
        -Passed ($actualKey -eq $item.PartitionKey) -Detail "Found $actualKey."

    if ($item.MaxThroughput) {
        $throughput = & az cosmosdb sql container throughput show `
            --account-name $AccountName --resource-group $ResourceGroup `
            --database-name $item.Database --name $item.Name --output json 2>$null | ConvertFrom-Json

        $max = $throughput.resource.autoscaleSettings.maxThroughput
        Test-Condition -Name "  autoscale max $($item.MaxThroughput) RU/s" -Passed ($max -eq $item.MaxThroughput) `
            -Detail "Found $(if ($max) { "$max RU/s autoscale" } else { 'manual throughput' })."
    }
}

Write-Host ''
Write-Host 'Data plane' -ForegroundColor Cyan

if ($LabProfile -eq 'core') {
    # The token audience is the bare host. documentEndpoint carries an explicit ':443',
    # which yields a token the service rejects with a 401.
    $resource = 'https://{0}' -f ([Uri]$endpoint).Host
    $token = (& az account get-access-token --resource $resource --query accessToken --output tsv).Trim()

    # The exercise on throughput and consistency point-reads this item.
    $itemId = '0A7E57DA-C73F-467F-954F-17B7AFD6227E'
    $partitionKey = '4F34E180-384D-42FC-AC10-FEC30227577F'

    $headers = @{
        'Authorization'                = [uri]::EscapeDataString("type=aad&ver=1.0&sig=$token")
        'x-ms-version'                 = '2018-12-31'
        'x-ms-date'                    = [DateTime]::UtcNow.ToString('r')
        'x-ms-documentdb-partitionkey' = '["' + $partitionKey + '"]'
    }

    $uri = "$($endpoint.TrimEnd('/'))/dbs/cosmicworks/colls/product/docs/$itemId"

    try {
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -UseBasicParsing
        $item = $response.Content | ConvertFrom-Json
        $charge = $response.Headers['x-ms-request-charge']

        Test-Condition -Name 'Authenticated point read succeeds' -Passed $true
        Test-Condition -Name "Item is 'ML Road Pedal'" -Passed ($item.name -eq 'ML Road Pedal') -Detail "Found '$($item.name)'."
        Write-Host "        Request charge: $charge RU" -ForegroundColor DarkGray
    }
    catch {
        $status = $null
        if ($_.Exception.Response) { $status = $_.Exception.Response.StatusCode.value__ }

        $detail = switch ($status) {
            401 { 'Token rejected. Check the Authorization header encoding in setup.ps1.' }
            403 { 'Authorized but forbidden. The role assignment may still be propagating.' }
            404 { 'Item not found. The catalog did not load. Re-run setup.ps1 without -SkipSeed.' }
            default { $_.Exception.Message }
        }

        Test-Condition -Name 'Authenticated point read succeeds' -Passed $false -Detail "HTTP $status. $detail"
    }
}

Write-Host ''
if ($script:Failures -eq 0) {
    Write-Host 'All checks passed. The environment is ready.' -ForegroundColor Green
    exit 0
}

Write-Host "$script:Failures check(s) failed." -ForegroundColor Red
exit 1
