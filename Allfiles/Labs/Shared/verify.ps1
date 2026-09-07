<#
.SYNOPSIS
    Verifies that a lab account is correctly provisioned for a DP-420 exercise.

.DESCRIPTION
    Checks the account configuration, the containers a lab profile expects, the
    data-plane role assignment, and an authenticated read against seeded data.

    The final check uses the same Microsoft Entra ID token path that setup.ps1
    uses to write items, so it confirms authentication end to end.

    Every profile setup.ps1 offers has an entry in $Expectations below. The script
    compares the two lists on startup and fails if they diverge.

.PARAMETER LabProfile
    The profile setup.ps1 was run with. The fleet profile creates two accounts,
    so run this script once per account.

.EXAMPLE
    ./verify.ps1 -ResourceGroup dp420 -AccountName dp420-cosmos-abc123

.EXAMPLE
    ./verify.ps1 -ResourceGroup dp420-monitoring -AccountName dp420lab14a7f3k9 -LabProfile monitoring
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$AccountName,

    [ValidateSet('core', 'modeling', 'security', 'backup', 'multiregion', 'indexing', 'monitoring', 'mirroring', 'fleet', 'search', 'agentmemory')]
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

#region Expectations

# One entry per setup.ps1 lab profile.
#   Account.DataPlaneRole     $false when the profile deliberately grants the signed-in user nothing.
#   SeededProduct             $true when cosmicworks/product holds the CosmicWorks catalog, which
#                             is what the data-plane point read at the end of this script reads.
$Expectations = @{
    core        = @{
        Account       = @{}
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product';     PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'cosmicworks'; Name = 'productMeta'; PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 237 }
            @{ Database = 'cosmicworks'; Name = 'leases';      PartitionKey = '/id';         Throughput    = 400 }
            @{ Database = 'cosmicworks'; Name = 'operations';  PartitionKey = '/categoryId'; MaxThroughput = 1000 }
            @{ Database = 'cosmicworks'; Name = 'bulkload';    PartitionKey = '/categoryId'; MaxThroughput = 1000 }
        )
    }
    modeling    = @{
        Account       = @{}
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'database-v1'; Name = 'customer';         PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 10 }
            @{ Database = 'database-v1'; Name = 'customerAddress';  PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 10 }
            @{ Database = 'database-v1'; Name = 'customerPassword'; PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 10 }
            @{ Database = 'database-v1'; Name = 'product';          PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'database-v1'; Name = 'productCategory';  PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 37 }
            @{ Database = 'database-v1'; Name = 'productTag';       PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 200 }
            @{ Database = 'database-v1'; Name = 'productTags';      PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 767 }
            @{ Database = 'database-v1'; Name = 'salesOrder';       PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 272 }
            @{ Database = 'database-v1'; Name = 'salesOrderDetail'; PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 610 }

            @{ Database = 'database-v2'; Name = 'customer';         PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 10 }
            @{ Database = 'database-v2'; Name = 'product';          PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'database-v2'; Name = 'productCategory';  PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 37 }
            @{ Database = 'database-v2'; Name = 'productTag';       PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 200 }
            @{ Database = 'database-v2'; Name = 'salesOrder';       PartitionKey = '/customerId'; MaxThroughput = 1000; MinItems = 272 }

            @{ Database = 'database-v3'; Name = 'customer';         PartitionKey = '/id';         MaxThroughput = 1000; MinItems = 10 }
            @{ Database = 'database-v3'; Name = 'product';          PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'database-v3'; Name = 'productCategory';  PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 37 }
            @{ Database = 'database-v3'; Name = 'productTag';       PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 200 }
            @{ Database = 'database-v3'; Name = 'salesOrder';       PartitionKey = '/customerId'; MaxThroughput = 1000; MinItems = 272 }

            @{ Database = 'database-v4'; Name = 'customer';         PartitionKey = '/customerId'; MaxThroughput = 1000; MinItems = 282 }
            @{ Database = 'database-v4'; Name = 'product';          PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'database-v4'; Name = 'productMeta';      PartitionKey = '/type';       MaxThroughput = 1000; MinItems = 237 }
        )
    }
    security    = @{
        # The exercise grants scoped roles to a hosted managed identity, so the signed-in
        # user starts with none and the container starts empty.
        Account       = @{ Serverless = $true; PublicNetworkAccess = 'Enabled'; DataPlaneRole = $false }
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId' }
        )
    }
    backup      = @{
        # The exercise loads the catalog itself, so the container is empty at this point.
        Account       = @{ BackupPolicy = 'Continuous'; ContinuousTier = 'Continuous7Days' }
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; Throughput = 400 }
        )
    }
    multiregion = @{
        Account       = @{ RegionCount = 2 }
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
        )
    }
    indexing    = @{
        # Global secondary indexes require continuous backup on the account.
        Account       = @{ BackupPolicy = 'Continuous'; ContinuousTier = 'Continuous7Days' }
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
        )
    }
    monitoring  = @{
        # Manual throughput, so the exercise can drive the container into rate limiting.
        Account       = @{}
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; Throughput = 400; MinItems = 295 }
        )
    }
    mirroring   = @{
        # Fabric mirroring requires continuous backup on the account.
        Account       = @{ BackupPolicy = 'Continuous'; ContinuousTier = 'Continuous7Days' }
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
            @{ Database = 'cosmicworks'; Name = 'customer'; PartitionKey = '/customerId'; MaxThroughput = 1000; MinItems = 282 }
        )
    }
    fleet       = @{
        Account       = @{ AccountCount = 2 }
        SeededProduct = $true
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; MinItems = 295 }
        )
    }
    search      = @{
        # The exercise builds the searchable text and calls the embedding model itself,
        # so the container starts empty and there is no cosmicworks/product to read.
        Account       = @{ Capabilities = @('EnableNoSQLVectorSearch') }
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'cosmicworks'; Name = 'productSearch'; PartitionKey = '/categoryId'; MaxThroughput = 1000 }
        )
    }
    agentmemory = @{
        # Both containers start empty. The exercise writes the turns and distills the
        # memories itself, so there is no cosmicworks/product to read here either.
        Account       = @{ Capabilities = @('EnableNoSQLVectorSearch') }
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'agentmemory'; Name = 'conversation'; PartitionKey = '/threadId'; MaxThroughput = 1000 }
            @{ Database = 'agentmemory'; Name = 'memory'; PartitionKey = '/userId'; MaxThroughput = 1000 }
        )
    }
}

# This script keeps its own copy of what each profile provisions, so it can silently fall
# behind setup.ps1 when a profile is added. Comparing the two lists turns that into a
# loud failure instead of a profile nobody verifies.
function Assert-ProfileParity {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $setupPath = Join-Path $root 'setup.ps1'

    if (-not (Test-Path -LiteralPath $setupPath)) {
        Write-Warning "setup.ps1 isn't beside this script, so its lab profiles can't be compared against the ones verified here."
        return
    }

    $match = [regex]::Match((Get-Content -LiteralPath $setupPath -Raw), "ValidateSet\(([^)]*)\)")
    if (-not $match.Success) { return }

    $declared = ($match.Groups[1].Value -replace "['\s]", '') -split ',' | Where-Object { $_ }
    $missing = @($declared | Where-Object { $_ -notin $Expectations.Keys })

    if ($missing.Count -gt 0) {
        throw "setup.ps1 provisions lab profile(s) this script has no expectations for: $($missing -join ', '). Add them to the `$Expectations table in verify.ps1."
    }
}

Assert-ProfileParity

#endregion

Write-Host "Verifying '$AccountName' for the $LabProfile lab profile." -ForegroundColor Cyan
Write-Host ''

if ($Expectations[$LabProfile].Account.AccountCount -gt 1) {
    Write-Host "  The $LabProfile profile creates $($Expectations[$LabProfile].Account.AccountCount) accounts. Run this script once per account." -ForegroundColor DarkGray
    Write-Host ''
}

Write-Host 'Account' -ForegroundColor Cyan
$account = & az cosmosdb show --name $AccountName --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json

if (-not $account) {
    Write-Host "  FAIL  Account not found in resource group '$ResourceGroup'." -ForegroundColor Red
    exit 1
}

$accountExpected = $Expectations[$LabProfile].Account

Test-Condition -Name 'Account exists' -Passed $true
Test-Condition -Name 'Key-based authentication disabled' -Passed ($account.disableLocalAuth -eq $true) `
    -Detail 'Expected disableLocalAuth = true. Re-run setup.ps1 or set it with az cosmosdb update --disable-local-auth true.'
Test-Condition -Name 'API is NoSQL' -Passed ($account.kind -eq 'GlobalDocumentDB')

if ($accountExpected.Serverless) {
    # setup.ps1 asks for serverless with --capabilities EnableServerless; capacityMode is the
    # newer property reporting the same thing, so either one confirms it.
    $isServerless = (@($account.capabilities.name) -contains 'EnableServerless') -or ($account.capacityMode -eq 'Serverless')
    Test-Condition -Name 'Capacity mode is serverless' -Passed $isServerless `
        -Detail 'Serverless can only be chosen when the account is created. Delete the account and re-run setup.ps1.'
}

if ($accountExpected.PublicNetworkAccess) {
    Test-Condition -Name "Public network access is $($accountExpected.PublicNetworkAccess)" `
        -Passed ($account.publicNetworkAccess -eq $accountExpected.PublicNetworkAccess) `
        -Detail "Found '$($account.publicNetworkAccess)'. The exercise starts from this state and changes it."
}

if ($accountExpected.BackupPolicy) {
    Test-Condition -Name "Backup policy is $($accountExpected.BackupPolicy)" `
        -Passed ($account.backupPolicy.type -eq $accountExpected.BackupPolicy) `
        -Detail "Found '$($account.backupPolicy.type)'. Backup mode can only be chosen when the account is created."
}

if ($accountExpected.ContinuousTier) {
    Test-Condition -Name "Continuous backup tier is $($accountExpected.ContinuousTier)" `
        -Passed ($account.backupPolicy.continuousModeProperties.tier -eq $accountExpected.ContinuousTier) `
        -Detail "Found '$($account.backupPolicy.continuousModeProperties.tier)'."
}

if ($accountExpected.RegionCount) {
    $regions = @($account.locations)
    Test-Condition -Name "Account spans $($accountExpected.RegionCount) regions" `
        -Passed ($regions.Count -eq $accountExpected.RegionCount) `
        -Detail "Found $($regions.Count): $(($regions.locationName) -join ', ')."
}

foreach ($capability in @($accountExpected.Capabilities)) {
    if (-not $capability) { continue }
    Test-Condition -Name "Account capability '$capability' is enabled" `
        -Passed (@($account.capabilities.name) -contains $capability) `
        -Detail "Found: $((@($account.capabilities.name) -join ', ')). This capability can take up to 15 minutes to appear after it is requested."
}

$endpoint = $account.documentEndpoint
Write-Host "        Endpoint: $endpoint" -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Role assignment' -ForegroundColor Cyan
$principalId = (& az ad signed-in-user show --query id --output tsv).Trim()
$assignments = & az cosmosdb sql role assignment list --account-name $AccountName --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json
$hasContributor = @($assignments | Where-Object {
        $_.principalId -eq $principalId -and $_.roleDefinitionId -match '0000000000000000000000000000000000000002|00000000-0000-0000-0000-000000000002'
    }).Count -gt 0

if ($accountExpected.DataPlaneRole -eq $false) {
    Test-Condition -Name 'Signed-in user holds no data-plane role' -Passed (-not $hasContributor) `
        -Detail 'This exercise measures a hosted managed identity gaining and losing access, so your own identity must start with none.'
}
else {
    Test-Condition -Name 'Signed-in user holds Built-in Data Contributor' -Passed $hasContributor `
        -Detail 'Without this role every data operation returns 403.'
}

Write-Host ''
Write-Host 'Containers' -ForegroundColor Cyan

$expected = $Expectations[$LabProfile].Containers

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
    elseif ($item.Throughput) {
        $throughput = & az cosmosdb sql container throughput show `
            --account-name $AccountName --resource-group $ResourceGroup `
            --database-name $item.Database --name $item.Name --output json 2>$null | ConvertFrom-Json

        $manual = $throughput.resource.throughput
        $isAutoscale = [bool]$throughput.resource.autoscaleSettings.maxThroughput
        Test-Condition -Name "  manual $($item.Throughput) RU/s" -Passed (($manual -eq $item.Throughput) -and (-not $isAutoscale)) `
            -Detail "Found $(if ($isAutoscale) { 'autoscale' } else { "$manual RU/s manual" }). This exercise depends on a fixed ceiling."
    }
}

Write-Host ''
Write-Host 'Data plane' -ForegroundColor Cyan

if (-not $Expectations[$LabProfile].SeededProduct) {
    Write-Host "  SKIP  The $LabProfile profile doesn't seed cosmicworks/product, so there's nothing to read yet." -ForegroundColor DarkGray
}
else {
    # The token audience is the bare host. documentEndpoint carries an explicit ':443',
    # which yields a token the service rejects with a 401.
    $resource = 'https://{0}' -f ([Uri]$endpoint).Host
    $token = (& az account get-access-token --resource $resource --query accessToken --output tsv).Trim()

    # A real item from the seeded CosmicWorks catalog: 'ML Road Pedal' in the Pedals category.
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
