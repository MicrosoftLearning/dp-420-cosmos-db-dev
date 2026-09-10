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

.PARAMETER EnableFoundry
    Also check the Foundry resource, project, model deployments, and user role.
    These are management-plane checks, not a model inference test.

.PARAMETER EmbeddingOnly
    With EnableFoundry, require only the embedding deployment.

.PARAMETER CheckMirroringPermissions
    With the mirroring profile, check account-scoped readMetadata and readAnalytics
    grants for the signed-in user after the custom-role task. This does not test Fabric.

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

    [ValidateSet('core', 'modeling', 'security', 'backup', 'multiregion', 'indexing', 'monitoring', 'mirroring', 'fleet', 'search', 'agentmemory', 'aitools')]
    [string]$LabProfile = 'core',

    [switch]$CheckMirroringPermissions,

    [switch]$EnableFoundry,

    [switch]$EmbeddingOnly,

    [string]$FoundryAccountName,

    [string]$FoundryProjectName = 'dp420',

    [string]$EmbeddingModel = 'text-embedding-3-small',

    [string]$EmbeddingModelVersion = '1',

    [string]$ChatModel = 'gpt-5.4-mini',

    [string]$ChatModelVersion = '2026-03-17'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Failures = 0

if ($EmbeddingOnly -and -not $EnableFoundry) { throw '-EmbeddingOnly requires -EnableFoundry.' }
if ($CheckMirroringPermissions -and $LabProfile -ne 'mirroring') { throw '-CheckMirroringPermissions requires -LabProfile mirroring.' }

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

function Test-AccountAccessConfiguration {
    param($Account, $Expected)

    if ($Expected.RequireAllNetworks) {
        $allNetworks = $Account.publicNetworkAccess -eq 'Enabled' -and
            @($Account.ipRules | Where-Object { $_ }).Count -eq 0 -and
            -not $Account.isVirtualNetworkFilterEnabled
        Test-Condition -Name 'Public network access allows all networks' -Passed $allNetworks `
            -Detail 'This lab uses all-network public access. Private-network mirroring needs separate Network ACL Bypass configuration; do not remove existing restrictions automatically.'
    }

    if ($Expected.RequireSingleWriteLocation) {
        Test-Condition -Name 'Account uses a single write region' -Passed (-not $Account.enableMultipleWriteLocations) `
            -Detail 'The mirroring lab requires single-region writes. Existing write-region settings are not changed.'
    }
}

function Test-MirroringPermissions {
    param([string]$PrincipalId, [string]$AccountId, [object[]]$Assignments)

    $definitionJson = & az cosmosdb sql role definition list --account-name $AccountName --resource-group $ResourceGroup --output json
    if ($LASTEXITCODE -ne 0) {
        Test-Condition -Name 'Mirroring role definitions can be read' -Passed $false `
            -Detail 'Unable to list Cosmos DB data-plane role definitions. Check Azure permissions and rerun verification.'
        return
    }
    $definitions = $definitionJson | ConvertFrom-Json
    $accountAssignments = @($Assignments | Where-Object {
        $_.principalId -eq $PrincipalId -and
        ($_.scope -eq '/' -or ([string]$_.scope).TrimEnd('/') -eq $AccountId.TrimEnd('/'))
    })
    $dataActions = @(foreach ($assignment in $accountAssignments) {
        $role = $definitions | Where-Object { $_.id -eq $assignment.roleDefinitionId }
        foreach ($permission in $role.permissions) { $permission.dataActions }
    })

    foreach ($action in 'Microsoft.DocumentDB/databaseAccounts/readMetadata', 'Microsoft.DocumentDB/databaseAccounts/readAnalytics') {
        $granted = @($dataActions | Where-Object { $_ -and $action -like $_ }).Count -gt 0
        Test-Condition -Name "Signed-in user has account-scoped $($action.Split('/')[-1])" -Passed $granted `
            -Detail 'Complete the custom-role task using the identity that connects from Fabric, then rerun this check.'
    }
    Write-Host '  Role configuration checked. Fabric connection, propagation, and replication still require portal validation.' -ForegroundColor DarkGray
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
        Account       = @{ BackupPolicy = 'Continuous'; ContinuousTier = 'Continuous7Days'; RequireAllNetworks = $true; RequireSingleWriteLocation = $true }
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
            @{ Database = 'cosmicworks'; Name = 'productSearch'; PartitionKey = '/categoryId'; MaxThroughput = 1000; VectorPath = '/embedding'; VectorDimensions = 1536; VectorIndexType = 'diskANN'; TextPath = '/searchText' }
        )
    }
    agentmemory = @{
        # Both containers start empty. The exercise writes the turns and distills the
        # memories itself, so there is no cosmicworks/product to read here either.
        Account       = @{ Capabilities = @('EnableNoSQLVectorSearch', 'DeleteAllItemsByPartitionKey') }
        SeededProduct = $false
        Containers    = @(
            @{ Database = 'agentmemory'; Name = 'conversation'; PartitionKey = '/threadId'; MaxThroughput = 1000; DefaultTtl = 2592000 }
            @{ Database = 'agentmemory'; Name = 'memory'; PartitionKey = '/userId'; MaxThroughput = 1000; DefaultTtl = -1; VectorPath = '/embedding'; VectorDimensions = 1536; VectorIndexType = 'quantizedFlat'; TextPath = '/content' }
        )
    }
}

$Expectations.aitools = @{
    Account = @{ Capabilities = @('EnableNoSQLVectorSearch') }
    SeededProduct = $true
    Containers = @($Expectations.core.Containers) + @(
        @{ Database = 'ai_memory'; Name = 'memories'; PartitionKey = @('/user_id', '/thread_id'); MaxThroughput = 1000; DefaultTtl = -1; VectorPath = '/embedding'; VectorDimensions = 1536; VectorIndexType = 'quantizedFlat'; TextPath = '/content' }
        @{ Database = 'ai_memory'; Name = 'memories_turns'; PartitionKey = @('/user_id', '/thread_id'); MaxThroughput = 1000; DefaultTtl = 2592000; VectorPath = '/embedding'; VectorDimensions = 1536; VectorIndexType = 'quantizedFlat'; TextPath = '/content' }
        @{ Database = 'ai_memory'; Name = 'memories_summaries'; PartitionKey = @('/user_id', '/thread_id'); MaxThroughput = 1000; DefaultTtl = -1; VectorPath = '/embedding'; VectorDimensions = 1536; VectorIndexType = 'quantizedFlat'; TextPath = '/content'; SummaryComposite = $true }
        @{ Database = 'ai_memory'; Name = 'counter'; PartitionKey = @('/user_id', '/thread_id'); MaxThroughput = 1000 }
        @{ Database = 'ai_memory'; Name = 'leases'; PartitionKey = '/id'; MaxThroughput = 1000 }
    )
}

function Test-ContainerConfiguration {
    param([object]$Resource, [hashtable]$Expected)

    $label = "$($Expected.Database)/$($Expected.Name)"
    $actualKey = @($Resource.partitionKey.paths) -join ', '
    $expectedKey = @($Expected.PartitionKey) -join ', '
    Test-Condition -Name "Container $label on $expectedKey" -Passed ($actualKey -eq $expectedKey) -Detail "Found $actualKey."
    if (@($Expected.PartitionKey).Count -gt 1) {
        Test-Condition -Name "$label hierarchical key kind and version" `
            -Passed ($Resource.partitionKey.kind -eq 'MultiHash' -and $Resource.partitionKey.version -eq 2)
    }
    if ($Expected.ContainsKey('DefaultTtl')) {
        Test-Condition -Name "$label default TTL $($Expected.DefaultTtl)" -Passed ($Resource.defaultTtl -eq $Expected.DefaultTtl)
    }
    if ($Expected.VectorPath) {
        $vector = $Resource.vectorEmbeddingPolicy.vectorEmbeddings | Where-Object path -eq $Expected.VectorPath
        Test-Condition -Name "$label vector policy" -Passed (
            @($vector).Count -eq 1 -and $vector.dimensions -eq $Expected.VectorDimensions -and
            $vector.dataType -eq 'float32' -and $vector.distanceFunction -eq 'cosine'
        )
        $index = $Resource.indexingPolicy.vectorIndexes | Where-Object { $_.path -eq $Expected.VectorPath -and $_.type -ceq $Expected.VectorIndexType }
        Test-Condition -Name "$label vector index $($Expected.VectorIndexType)" -Passed (@($index).Count -eq 1)
    }
    if ($Expected.TextPath) {
        $textPolicy = $Resource.fullTextPolicy.fullTextPaths | Where-Object { $_.path -eq $Expected.TextPath -and $_.language -eq 'en-US' }
        $textIndex = $Resource.indexingPolicy.fullTextIndexes | Where-Object path -eq $Expected.TextPath
        Test-Condition -Name "$label full-text policy and index" -Passed (@($textPolicy).Count -eq 1 -and @($textIndex).Count -eq 1)
    }
    if ($Expected.SummaryComposite) {
        $found = $false
        foreach ($index in $Resource.indexingPolicy.compositeIndexes) {
            $paths = @($index | ForEach-Object { "$($_.path):$($_.order)" }) -join ','
            if ($paths -eq '/user_id:ascending,/thread_id:ascending,/version:descending') { $found = $true }
        }
        Test-Condition -Name "$label summary composite index" -Passed $found
    }
}

function Test-FoundryResources {
    param([string]$PrincipalId)

    $name = if ($FoundryAccountName) { $FoundryAccountName } else { "$AccountName-ai" }
    $foundry = & az cognitiveservices account show --name $name --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $foundry) {
        Test-Condition -Name "Foundry resource $name" -Passed $false -Detail 'Run setup.ps1 with -EnableFoundry, or pass the FoundryAccountName used during setup.'
        return
    }
    Test-Condition -Name 'Foundry is ready and keyless' -Passed (
        $foundry.kind -eq 'AIServices' -and $foundry.properties.allowProjectManagement -and
        $foundry.properties.disableLocalAuth -eq $true -and $foundry.properties.provisioningState -eq 'Succeeded'
    )
    $projects = & az rest --method GET --url "https://management.azure.com$($foundry.id)/projects?api-version=2025-06-01" --output json 2>$null | ConvertFrom-Json
    $project = $projects.value | Where-Object { ($_.name -split '/')[-1] -eq $FoundryProjectName }
    Test-Condition -Name "Foundry project $FoundryProjectName" -Passed ($LASTEXITCODE -eq 0 -and @($project).Count -eq 1)

    $deployments = & az cognitiveservices account deployment list --name $name --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json
    $deploymentListSucceeded = $LASTEXITCODE -eq 0
    $models = @(@{ Name = $EmbeddingModel; Version = $EmbeddingModelVersion })
    if (-not $EmbeddingOnly) { $models += @{ Name = $ChatModel; Version = $ChatModelVersion } }
    foreach ($model in $models) {
        $deployment = $deployments | Where-Object name -eq $model.Name | Select-Object -First 1
        Test-Condition -Name "Model deployment $($model.Name)" -Passed (
            $deploymentListSucceeded -and $deployment -and $deployment.properties.provisioningState -eq 'Succeeded' -and
            $deployment.properties.model.name -eq $model.Name -and $deployment.properties.model.version -eq $model.Version -and
            $deployment.sku.name -in @('Standard', 'GlobalStandard', 'DataZoneStandard')
        ) -Detail 'Check the deployment state, model version, regional availability, and quota.'
    }

    $roles = & az role assignment list --scope $foundry.id --include-inherited --output json 2>$null | ConvertFrom-Json
    $role = $roles | Where-Object {
        $_.principalId -eq $PrincipalId -and $_.roleDefinitionId -like '*/53ca6127-db72-4b80-b1b0-d745d6d5456d'
    }
    Test-Condition -Name 'Signed-in user holds Foundry User' -Passed ($LASTEXITCODE -eq 0 -and @($role).Count -gt 0)
    Write-Host '  Model resources and role assignments checked. Inference calls can still require role propagation.' -ForegroundColor DarkGray
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
Test-AccountAccessConfiguration -Account $account -Expected $accountExpected

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
        -Detail "Found '$($account.backupPolicy.type)'. Setup does not migrate backup mode on existing accounts."
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

if ($CheckMirroringPermissions) {
    Test-MirroringPermissions -PrincipalId $principalId -AccountId $account.id -Assignments @($assignments)
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

    Test-ContainerConfiguration -Resource $container.resource -Expected $item

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

if ($EnableFoundry) {
    Write-Host ''
    Write-Host 'Foundry' -ForegroundColor Cyan
    Test-FoundryResources -PrincipalId $principalId
}

Write-Host ''
if ($script:Failures -eq 0) {
    if ($LabProfile -eq 'mirroring') {
        Write-Host 'Cosmos DB checks passed. Fabric capacity, connection, and replication are checked in the exercise.' -ForegroundColor Green
    }
    else {
        Write-Host 'All checks passed. The environment is ready.' -ForegroundColor Green
    }
    exit 0
}

Write-Host "$script:Failures check(s) failed." -ForegroundColor Red
exit 1
