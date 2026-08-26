<#
.SYNOPSIS
    Provisions and seeds the Azure Cosmos DB environment used by the DP-420 exercises.

.DESCRIPTION
    Creates a resource group, an Azure Cosmos DB for NoSQL account with key-based
    authentication disabled, the databases and containers a given lab profile needs,
    and a data-plane role assignment for the signed-in user. Optionally loads the
    CosmicWorks sample data.

    Every operation is idempotent, so the script is safe to re-run.

.PARAMETER LabProfile
    core     - cosmicworks database with product, productMeta, leases, bulkload.
               Serves the resources, SDK, operations, query, change feed, and
               AI-assisted tools exercises.
    modeling - database-v1 through database-v4, for the data modeling and
               partitioning exercise.

.PARAMETER AccountName
    Optional. Target an account that already exists. When omitted, the script
    generates a globally unique name from NamePrefix and reports it.

.PARAMETER NamePrefix
    Prefix for a generated account name. The script appends six random
    alphanumeric characters to keep the name globally unique.

.PARAMETER SkipSeed
    Provision the databases and containers, but do not load any data.

.EXAMPLE
    ./setup.ps1 -ResourceGroup dp420 -Location eastus -NamePrefix dp420lab02

.EXAMPLE
    ./setup.ps1 -ResourceGroup dp420 -AccountName dp420lab02a7f3k9 -LabProfile modeling
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$AccountName,

    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,30}$')]
    [string]$NamePrefix = 'dp420lab',

    [ValidateSet('core', 'modeling')]
    [string]$LabProfile = 'core',

    [string]$Location = 'eastus',

    [switch]$SkipSeed
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DataRoot = 'https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data'
$DataContributorRoleId = '00000000-0000-0000-0000-000000000002'

# Container copy jobs run in the account's write region and are unavailable elsewhere.
# The change-feed exercise fails at its final task if the account sits outside this list.
$ContainerCopyRegions = @(
    'australiacentral', 'australiacentral2', 'australiaeast', 'australiasoutheast',
    'brazilsouth', 'canadacentral', 'canadaeast', 'centralindia', 'centralus',
    'eastasia', 'eastus', 'eastus2', 'francecentral', 'francesouth',
    'germanynorth', 'germanywestcentral', 'israelcentral', 'japaneast', 'japanwest',
    'koreacentral', 'malaysiasouth', 'northcentralus', 'northeurope', 'norwayeast',
    'norwaywest', 'southafricanorth', 'southcentralus', 'southeastasia',
    'switzerlandnorth', 'switzerlandwest', 'uaecentral', 'uksouth', 'ukwest',
    'westcentralus', 'westeurope', 'westindia', 'westus', 'westus2'
)

# Autoscale maxima. The billed floor is 10% of the maximum, so 1000 keeps an
# abandoned lab account at a 100 RU/s baseline.
$Profiles = @{
    core     = @{
        Databases  = @(
            @{
                Name       = 'cosmicworks'
                Containers = @(
                    @{ Name = 'product';     PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                    @{ Name = 'productMeta'; PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v4/productMeta" }
                    @{ Name = 'leases';      PartitionKey = '/id';         Throughput    = 400 }
                    @{ Name = 'bulkload';    PartitionKey = '/categoryId'; MaxThroughput = 1000 }
                )
            }
        )
    }
    modeling = @{
        # Container names and partition keys are discovered from the CosmicWorks
        # repository at run time, because they differ at every modeling stage.
        Discover = @('database-v1', 'database-v2', 'database-v3', 'database-v4')
    }
}

function Write-Log {
    param([string]$Message)

    if (-not $script:LogPath) { return }
    "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message | Add-Content -LiteralPath $script:LogPath -Encoding utf8
}

function Initialize-Log {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $directory = Join-Path $root 'logs'

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $script:LogPath = Join-Path $directory ('setup-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    Write-Host "Logging to $script:LogPath" -ForegroundColor DarkGray

    Write-Log 'setup.ps1'
    Write-Log "ResourceGroup  : $ResourceGroup"
    Write-Log "AccountName    : $(if ($AccountName) { $AccountName } else { '(generated)' })"
    Write-Log "NamePrefix     : $NamePrefix"
    Write-Log "LabProfile     : $LabProfile"
    Write-Log "Location       : $Location"
    Write-Log "SkipSeed       : $SkipSeed"
    Write-Log "PSVersion      : $($PSVersionTable.PSVersion)"
    Write-Log "OS             : $([System.Environment]::OSVersion.VersionString)"
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
    Write-Log "STEP $Message"
}

function Invoke-Az {
    param([string[]]$Arguments)

    $command = "az $($Arguments -join ' ')"
    Write-Log "RUN  $command"

    # Capture stderr to a file rather than merging it into stdout. Merging corrupts
    # every caller that parses the result as JSON or TSV.
    $errorFile = [System.IO.Path]::GetTempFileName()
    $previousPreference = $ErrorActionPreference

    try {
        # Some PowerShell 7 builds turn redirected native stderr into a terminating error.
        $ErrorActionPreference = 'Continue'
        $output = & az @Arguments 2>$errorFile
        $exitCode = $LASTEXITCODE
        $stderr = (Get-Content -LiteralPath $errorFile -Raw)
    }
    finally {
        $ErrorActionPreference = $previousPreference
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }

    Write-Log "EXIT $exitCode"
    if ($output) { Write-Log "OUT  $($output -join [Environment]::NewLine)" }

    if ($stderr) {
        Write-Log "ERR  $($stderr.TrimEnd())"
        Write-Host $stderr.TrimEnd() -ForegroundColor DarkYellow
    }

    if ($exitCode -ne 0) {
        throw "$command failed with exit code $exitCode."
    }

    return $output
}

function Assert-Prerequisites {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'The Azure CLI is not installed. See https://learn.microsoft.com/cli/azure/install-azure-cli.'
    }

    $azPaths = @(Get-Command az -All | ForEach-Object { $_.Source })
    Write-Log "az on PATH     : $($azPaths -join ' | ')"

    if ($azPaths.Count -gt 1) {
        Write-Warning "More than one 'az' is on PATH. The first one wins: $($azPaths[0])"
    }

    $version = & az version --output json 2>$null | ConvertFrom-Json
    Write-Log "az version     : $($version.'azure-cli')"

    $account = & az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "You are not signed in to the Azure CLI. Run 'az login' and try again."
    }

    Write-Step "Signed in as $($account.user.name) on subscription '$($account.name)'."

    if ($Location -notin $ContainerCopyRegions) {
        Write-Warning "Region '$Location' does not support container copy jobs. The change feed exercise cannot complete its final task in this region."
    }
}

function New-AccountName {
    param([string]$Prefix)

    # Lowercase letters and digits only, which is what Cosmos DB account names allow.
    $alphabet = (48..57) + (97..122)

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $suffix = -join ($alphabet | Get-Random -Count 6 | ForEach-Object { [char]$_ })
        $candidate = "$Prefix$suffix"

        $taken = (& az cosmosdb check-name-exists --name $candidate --output tsv 2>$null)
        if ($taken -eq 'false') {
            return $candidate
        }

        Write-Step "Name '$candidate' is already taken. Trying another."
    }

    throw "Could not find an available account name after 10 attempts. Try a different -NamePrefix."
}

function Initialize-Subscription {
    Write-Step "Registering the Microsoft.DocumentDB resource provider."
    Invoke-Az @('provider', 'register', '--namespace', 'Microsoft.DocumentDB', '--wait') | Out-Null

    $existingGroup = & az group show --name $ResourceGroup --output json 2>$null | ConvertFrom-Json

    if ($existingGroup) {
        Write-Step "Using existing resource group '$ResourceGroup' in $($existingGroup.location)."

        if ($existingGroup.location -ne $Location) {
            # A resource group's own location is only metadata, so this is worth stating but not blocking.
            Write-Step "The Azure Cosmos DB account is created in $Location regardless of the group's location."
        }

        return
    }

    Write-Step "Creating resource group '$ResourceGroup' in $Location."
    Invoke-Az @('group', 'create', '--name', $ResourceGroup, '--location', $Location) | Out-Null
}

function New-LabAccount {
    $existing = & az cosmosdb show --name $AccountName --resource-group $ResourceGroup --output json 2>$null
    if ($existing) {
        Write-Step "Account '$AccountName' already exists. Skipping creation."
        return ($existing | ConvertFrom-Json).documentEndpoint
    }

    Write-Step "Creating account '$AccountName'. This takes 5-10 minutes."
    $created = Invoke-Az @(
        'cosmosdb', 'create',
        '--name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--locations', "regionName=$Location", 'failoverPriority=0', 'isZoneRedundant=False',
        '--default-consistency-level', 'Session',
        '--disable-local-auth', 'true',
        '--output', 'json'
    )

    return ($created | ConvertFrom-Json).documentEndpoint
}

function Grant-DataPlaneAccess {
    Write-Step 'Assigning the Cosmos DB Built-in Data Contributor role to the signed-in user.'

    $principalId = (Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv')).Trim()

    $assignments = & az cosmosdb sql role assignment list `
        --account-name $AccountName --resource-group $ResourceGroup --output json 2>$null | ConvertFrom-Json

    $alreadyAssigned = $assignments | Where-Object {
        $_.principalId -eq $principalId -and $_.roleDefinitionId -match $DataContributorRoleId
    }

    if ($alreadyAssigned) {
        Write-Step 'Role assignment already present. Skipping.'
        return
    }

    Invoke-Az @(
        'cosmosdb', 'sql', 'role', 'assignment', 'create',
        '--account-name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--role-definition-id', $DataContributorRoleId,
        '--principal-id', $principalId,
        '--scope', '/'
    ) | Out-Null
}

function New-LabDatabase {
    param([string]$Name)

    $exists = (& az cosmosdb sql database exists `
        --account-name $AccountName --resource-group $ResourceGroup --name $Name --output tsv 2>$null)

    if ($exists -eq 'true') { return }

    Write-Step "Creating database '$Name'."
    Invoke-Az @(
        'cosmosdb', 'sql', 'database', 'create',
        '--account-name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--name', $Name
    ) | Out-Null
}

function New-LabContainer {
    param(
        [string]$Database,
        [hashtable]$Container
    )

    $exists = (& az cosmosdb sql container exists `
        --account-name $AccountName --resource-group $ResourceGroup `
        --database-name $Database --name $Container.Name --output tsv 2>$null)

    if ($exists -eq 'true') {
        Write-Step "Container '$Database/$($Container.Name)' already exists. Skipping."
        return
    }

    $arguments = @(
        'cosmosdb', 'sql', 'container', 'create',
        '--account-name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--database-name', $Database,
        '--name', $Container.Name,
        '--partition-key-path', $Container.PartitionKey
    )

    if ($Container.MaxThroughput) {
        $arguments += @('--max-throughput', $Container.MaxThroughput)
        $sizing = "autoscale to $($Container.MaxThroughput) RU/s"
    }
    else {
        $arguments += @('--throughput', $Container.Throughput)
        $sizing = "$($Container.Throughput) RU/s manual"
    }

    Write-Step "Creating container '$Database/$($Container.Name)' on $($Container.PartitionKey), $sizing."
    Invoke-Az $arguments | Out-Null
}

function Get-CosmosToken {
    param([string]$Endpoint)

    # documentEndpoint carries an explicit ':443', but the token audience is the bare
    # host, which is what the Cosmos DB SDKs request. Leaving the port on produces a
    # token the service rejects with a 401.
    $resource = 'https://{0}' -f ([Uri]$Endpoint).Host
    return (Invoke-Az @('account', 'get-access-token', '--resource', $resource, '--query', 'accessToken', '--output', 'tsv')).Trim()
}

function Add-SeedData {
    param(
        [string]$Endpoint,
        [string]$Database,
        [hashtable]$Container
    )

    if (-not $Container.Seed) { return }

    Write-Step "Loading $($Container.Name) from $($Container.Seed)."
    $items = Invoke-RestMethod -Uri $Container.Seed -Method Get

    $token = Get-CosmosToken -Endpoint $Endpoint
    $partitionKeyProperty = $Container.PartitionKey.TrimStart('/')
    $uri = "$($Endpoint.TrimEnd('/'))/dbs/$Database/colls/$($Container.Name)/docs"
    $written = 0

    Write-Log "SEED POST $uri ($(@($items).Count) items, partition key property '$partitionKeyProperty')"

    foreach ($item in $items) {
        $partitionKeyValue = $item.$partitionKeyProperty

        # The header must be a JSON array. ConvertTo-Json unwraps a single-element
        # array, so build the brackets by hand and let it escape only the value.
        $partitionKeyHeader = '[' + ($partitionKeyValue | ConvertTo-Json -Compress) + ']'

        $headers = @{
            'Authorization'                 = [uri]::EscapeDataString("type=aad&ver=1.0&sig=$token")
            'x-ms-version'                  = '2018-12-31'
            'x-ms-date'                     = [DateTime]::UtcNow.ToString('r')
            'x-ms-documentdb-partitionkey'  = $partitionKeyHeader
            'x-ms-documentdb-is-upsert'     = 'true'
        }

        if ($written -eq 0) {
            # Enough of the first request to diagnose an auth or partition key rejection,
            # without writing the bearer token to disk.
            Write-Log "SEED first item id '$($item.id)', partition key header $partitionKeyHeader"
            Write-Log "SEED Authorization prefix '$(($headers.Authorization).Substring(0, 24))...' length $($headers.Authorization.Length)"
        }

        $body = [System.Text.Encoding]::UTF8.GetBytes(($item | ConvertTo-Json -Depth 20 -Compress))

        try {
            Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
            $written++
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            Write-Log "SEED FAILED after $written items. HTTP $status. $($_.ErrorDetails.Message)"

            if ($status -eq 401 -or $status -eq 403) {
                throw "Authorization failed writing to $($Container.Name) (HTTP $status). A new role assignment can take a few minutes to propagate. Wait, then re-run this script."
            }
            throw "Failed writing an item to $($Container.Name): $_"
        }
    }

    Write-Log "SEED loaded $written items into $($Container.Name)."
    Write-Host "    Loaded $written items into $($Container.Name)." -ForegroundColor Green
}

function Get-ModelingLayout {
    # Each file in a CosmicWorks database folder is one container, named after the file.
    # Partition keys change between modeling stages, so read them from the items themselves.
    $layout = @()

    foreach ($database in $Profiles.modeling.Discover) {
        $listing = Invoke-RestMethod -Uri "https://api.github.com/repos/AzureCosmosDB/CosmicWorks/contents/data/$database" `
            -Headers @{ 'User-Agent' = 'dp-420-lab-setup' }

        $containers = foreach ($file in $listing | Where-Object { $_.type -eq 'file' }) {
            @{
                Name          = $file.name
                PartitionKey  = '/id'
                MaxThroughput = 1000
                Seed          = "$DataRoot/$database/$($file.name)"
            }
        }

        $layout += @{ Name = $database; Containers = $containers }
    }

    return $layout
}

Initialize-Log

trap {
    Write-Log "FAIL $($_.Exception.Message)"
    if ($_.ScriptStackTrace) { Write-Log $_.ScriptStackTrace }

    Write-Host ''
    Write-Host 'Setup failed. Include this log file when you ask for help:' -ForegroundColor Red
    Write-Host "  $script:LogPath" -ForegroundColor Yellow
    break
}

Assert-Prerequisites
Initialize-Subscription

if ($AccountName) {
    if ($AccountName -notmatch '^[a-z0-9][a-z0-9-]{1,42}[a-z0-9]$') {
        throw "'$AccountName' isn't a valid Azure Cosmos DB account name. Use 3-44 lowercase letters, numbers, and hyphens."
    }
}
else {
    # Re-use an account this script created earlier. Without this, a re-run after a
    # mid-script failure generates a fresh name and leaves a second billable account behind.
    $existing = @(& az cosmosdb list --resource-group $ResourceGroup `
            --query "[?starts_with(name, '$NamePrefix')].name" --output tsv 2>$null |
        Where-Object { $_ })

    if ($existing.Count -gt 0) {
        $AccountName = $existing[0].Trim()
        Write-Step "Reusing the existing account '$AccountName' in '$ResourceGroup'."
    }
    else {
        $AccountName = New-AccountName -Prefix $NamePrefix
        Write-Step "Generated account name '$AccountName'."
    }
}

$endpoint = New-LabAccount
Grant-DataPlaneAccess

if ($LabProfile -eq 'modeling') {
    Write-Warning 'The modeling profile discovers containers from the CosmicWorks repository and provisions every one on /id. Partition keys for database-v2 through database-v4 still need to be confirmed against the dataset before this profile is used in a published exercise.'
    $databases = Get-ModelingLayout
}
else {
    $databases = $Profiles[$LabProfile].Databases
}

foreach ($database in $databases) {
    New-LabDatabase -Name $database.Name

    foreach ($container in $database.Containers) {
        New-LabContainer -Database $database.Name -Container $container

        if (-not $SkipSeed) {
            Add-SeedData -Endpoint $endpoint -Database $database.Name -Container $container
        }
    }
}

Write-Host ''
Write-Host 'Setup complete. Record these two values.' -ForegroundColor Green
Write-Host ''
Write-Host "  Account name     : $AccountName" -ForegroundColor Yellow
Write-Host "  Account endpoint : $endpoint" -ForegroundColor Yellow
Write-Host ''
Write-Host "  Resource group   : $ResourceGroup"
Write-Host "  Location         : $Location"
Write-Host "  Lab profile      : $LabProfile"
Write-Host "  Log file         : $script:LogPath"
Write-Host ''
Write-Host 'Every exercise in this course asks for the account endpoint.'
