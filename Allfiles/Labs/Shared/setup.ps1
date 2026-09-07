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
    security - A disposable account for the security exercise. Serverless, with an
               empty cosmicworks/product container and no data-plane role for the
               signed-in user, because that exercise grants scoped roles to a hosted
               managed identity instead. Use a resource group of its own.
    backup   - A disposable account for the backup and restore exercise, created with
               continuous backup at the Continuous7Days tier and an empty
               cosmicworks/product container. Use a resource group of its own.
    multiregion - A disposable account for the multi-region availability and failover
               exercise, created in two regions with a seeded cosmicworks/product
               container. That exercise changes the write region and then takes a
               region offline, so use a resource group of its own.
    indexing - A disposable account for the indexing strategy exercise, created with
               continuous backup because global secondary indexes require it, and a
               seeded cosmicworks/product container on autoscale. Use a resource group
               of its own.
    monitoring - A disposable account for the monitoring and troubleshooting exercise,
               with a seeded cosmicworks/product container on 400 RU/s manual
               throughput so the exercise can drive it into rate limiting. That
               exercise attaches a diagnostic setting and an alert rule, then deletes
               the whole group, so use a resource group of its own.
    fleet    - Two disposable accounts for the fleets exercise, created with an
               identical single-region configuration so they can share one
               fleetspace throughput pool, each with a seeded cosmicworks/product
               container. That exercise deletes the whole group, so use a resource
               group of its own.

.PARAMETER AccountName
    Optional. Target an account that already exists. When omitted, the script
    generates a globally unique name from NamePrefix and reports it. Profiles that
    create more than one account don't accept this parameter.

.PARAMETER SecondaryLocation
    Second Azure region for the multiregion profile. When omitted, the script picks
    a nearby region for the chosen Location. Ignored by every other profile.

.PARAMETER NamePrefix
    Prefix for a generated account name. The script appends six random
    alphanumeric characters to keep the name globally unique.

.PARAMETER SkipSeed
    Provision the databases and containers, but do not load any data.

.PARAMETER SeedConcurrency
    How many seed writes to issue at once. Set to 1 to load serially when
    troubleshooting a seeding failure.

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

    [ValidateSet('core', 'modeling', 'security', 'backup', 'multiregion', 'indexing', 'monitoring', 'mirroring', 'fleet', 'search', 'agentmemory')]
    [string]$LabProfile = 'core',

    [string]$Location = 'westus2',

    [string]$SecondaryLocation,

    [ValidateRange(1, 32)]
    [int]$SeedConcurrency = 8,

    [switch]$SkipSeed
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Configuration

$DataRoot = 'https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data'
$DataContributorRoleId = '00000000-0000-0000-0000-000000000002'

# 2.61 is the first release whose behavior these commands rely on.
$MinimumCliVersion = [version]'2.61.0'

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

# Azure Cosmos DB replicates between any two regions, so these are convenience
# defaults for the multiregion profile rather than a required pairing.
$DefaultSecondaryLocation = @{
    australiaeast      = 'australiasoutheast'
    brazilsouth        = 'southcentralus'
    canadacentral      = 'canadaeast'
    centralindia       = 'southindia'
    centralus          = 'eastus2'
    eastasia           = 'southeastasia'
    eastus             = 'westus'
    eastus2            = 'centralus'
    francecentral      = 'westeurope'
    germanywestcentral = 'northeurope'
    japaneast          = 'japanwest'
    koreacentral       = 'koreasouth'
    northcentralus     = 'southcentralus'
    northeurope        = 'westeurope'
    southafricanorth   = 'northeurope'
    southcentralus     = 'northcentralus'
    southeastasia      = 'eastasia'
    swedencentral      = 'northeurope'
    switzerlandnorth   = 'westeurope'
    uksouth            = 'ukwest'
    ukwest             = 'uksouth'
    westcentralus      = 'westus2'
    westeurope         = 'northeurope'
    westus             = 'eastus'
    westus2            = 'westcentralus'
    westus3            = 'eastus'
}

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
                    @{ Name = 'operations';  PartitionKey = '/categoryId'; MaxThroughput = 1000 }
                    @{ Name = 'bulkload';    PartitionKey = '/categoryId'; MaxThroughput = 1000 }
                )
            }
        )
    }
    modeling = @{
        # Four stages of the same e-commerce data. Partition keys differ per stage,
        # so each container is declared explicitly rather than discovered.
        Databases = @(
            @{
                Name       = 'database-v1'
                Containers = @(
                    @{ Name = 'customer';         PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/customer" }
                    @{ Name = 'customerAddress';  PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/customerAddress" }
                    @{ Name = 'customerPassword'; PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/customerPassword" }
                    @{ Name = 'product';          PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/product" }
                    @{ Name = 'productCategory';  PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/productCategory" }
                    @{ Name = 'productTag';       PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/productTag" }
                    @{ Name = 'productTags';      PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/productTags" }
                    @{ Name = 'salesOrder';       PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/salesOrder" }
                    @{ Name = 'salesOrderDetail'; PartitionKey = '/id'; MaxThroughput = 1000; Seed = "$DataRoot/database-v1/salesOrderDetail" }
                )
            }
            @{
                Name       = 'database-v2'
                Containers = @(
                    @{ Name = 'customer';        PartitionKey = '/id';         MaxThroughput = 1000; Seed = "$DataRoot/database-v2/customer" }
                    @{ Name = 'product';         PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v2/product" }
                    @{ Name = 'productCategory'; PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v2/productCategory" }
                    @{ Name = 'productTag';      PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v2/productTag" }
                    @{ Name = 'salesOrder';      PartitionKey = '/customerId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v2/salesOrder" }
                )
            }
            @{
                Name       = 'database-v3'
                Containers = @(
                    @{ Name = 'customer';        PartitionKey = '/id';         MaxThroughput = 1000; Seed = "$DataRoot/database-v3/customer" }
                    @{ Name = 'product';         PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v3/product" }
                    @{ Name = 'productCategory'; PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v3/productCategory" }
                    @{ Name = 'productTag';      PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v3/productTag" }
                    @{ Name = 'salesOrder';      PartitionKey = '/customerId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v3/salesOrder" }
                )
            }
            @{
                Name       = 'database-v4'
                Containers = @(
                    @{ Name = 'customer';    PartitionKey = '/customerId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/customer" }
                    @{ Name = 'product';     PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                    @{ Name = 'productMeta'; PartitionKey = '/type';       MaxThroughput = 1000; Seed = "$DataRoot/database-v4/productMeta" }
                )
            }
        )
    }
    security = @{
        # The exercise disables public network access on this account and then deletes
        # the whole resource group, so it must never share either with the rest of the course.
        Account   = @{
            Dedicated            = $true
            Providers            = @('Microsoft.ContainerInstance')
            Serverless           = $true
            PublicNetworkAccess  = 'ENABLED'
            GrantDataPlaneAccess = $false
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                # Left empty on purpose. Loading the catalog through the hosted managed
                # identity is the first thing the exercise proves.
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId' }
                )
            }
        )
    }
    multiregion = @{
        # The exercise changes the write region and then takes a region offline. A
        # region that has been taken offline stays offline until Microsoft restores
        # it, so this account must never be the shared course account.
        Account   = @{
            Dedicated  = $true
            RegionCount = 2
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                )
            }
        )
    }
    indexing = @{
        # Global secondary indexes require continuous backup on the account, and
        # continuous backup can only be chosen at account creation, so this exercise
        # gets an account and a resource group of its own.
        Account   = @{
            Dedicated      = $true
            BackupPolicy   = 'Continuous'
            ContinuousTier = 'Continuous7Days'
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                )
            }
        )
    }
    monitoring = @{
        # The exercise attaches a diagnostic setting to this account and then deletes
        # the resource group. A diagnostic setting has to be removed before its target
        # resource is deleted or renamed, so keeping both in a group of their own means
        # one delete cleans up everything.
        Account   = @{
            Dedicated = $true
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                # Manual 400 RU/s rather than autoscale. The exercise has to reach rate
                # limiting inside a lab time budget, and an autoscale maximum would let
                # the container absorb the load instead of returning 429 responses.
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId'; Throughput = 400; Seed = "$DataRoot/database-v4/product" }
                )
            }
        )
    }
    mirroring = @{
        # Microsoft Fabric mirroring requires continuous backup on the account, and
        # continuous backup can only be chosen at account creation and can never be
        # turned off again, so this exercise gets an account and a resource group of
        # its own rather than altering the shared course account.
        Account   = @{
            Dedicated      = $true
            BackupPolicy   = 'Continuous'
            ContinuousTier = 'Continuous7Days'
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                # Two containers, seeded, because the exercise reads the mirrored data as
                # warehouse tables. The customer container holds two document types in one
                # container, which is what makes mirroring's union schema observable.
                Containers = @(
                    @{ Name = 'product';  PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                    @{ Name = 'customer'; PartitionKey = '/customerId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/customer" }
                )
            }
        )
    }
    fleet    = @{
        # A fleet groups accounts, so this profile creates two of them. Both are
        # created with the same single region and the same single-region write
        # configuration, because accounts can share a fleetspace throughput pool
        # only when their regions and their service tier match.
        Account   = @{
            Dedicated    = $true
            AccountCount = 2
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId'; MaxThroughput = 1000; Seed = "$DataRoot/database-v4/product" }
                )
            }
        )
    }
    search   = @{
        # Vector search is an account capability that can never be turned off, and the
        # search container's vector policy is fixed at creation, so this exercise gets
        # an account and a resource group of its own rather than altering the shared one.
        Account   = @{
            Dedicated    = $true
            Capabilities = @('EnableNoSQLVectorSearch')
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                Containers = @(
                    # Left empty on purpose. The exercise builds the searchable text and
                    # calls the embedding model itself, so seeding here would store items
                    # with no vector at the path the vector index covers.
                    @{
                        Name          = 'productSearch'
                        PartitionKey  = '/categoryId'
                        MaxThroughput = 1000
                        FullTextPolicy = @{
                            defaultLanguage = 'en-US'
                            fullTextPaths   = @(
                                @{ path = '/searchText'; language = 'en-US' }
                            )
                        }
                        VectorEmbeddings = @{
                            vectorEmbeddings = @(
                                @{
                                    path             = '/embedding'
                                    dataType         = 'float32'
                                    distanceFunction = 'cosine'
                                    dimensions       = 1536
                                }
                            )
                        }
                        IndexingPolicy = @{
                            indexingMode   = 'consistent'
                            automatic      = $true
                            includedPaths  = @(@{ path = '/*' })
                            excludedPaths  = @(
                                @{ path = '/"_etag"/?' }
                                @{ path = '/embedding/*' }
                            )
                            fullTextIndexes = @(@{ path = '/searchText' })
                            vectorIndexes   = @(@{ path = '/embedding'; type = 'diskANN' })
                        }
                    }
                )
            }
        )
    }
    agentmemory = @{
        # Vector search is an account capability that can never be turned off, so this
        # exercise gets an account and a resource group of its own rather than altering
        # the shared one. The two containers hold the module's two memory tiers.
        Account   = @{
            Dedicated    = $true
            Capabilities = @('EnableNoSQLVectorSearch')
        }
        Databases = @(
            @{
                Name       = 'agentmemory'
                Containers = @(
                    @{
                        # Short-term conversation state. Turns expire 30 days after their
                        # last write, so the log clears itself without a cleanup job.
                        Name          = 'conversation'
                        PartitionKey  = '/threadId'
                        MaxThroughput = 1000
                        DefaultTtl    = 2592000
                    }
                    @{
                        # Long-term derived memory, partitioned on the user because recall
                        # crosses every thread that user ever opened. DefaultTtl -1 enables
                        # time to live while expiring nothing by default, so an individual
                        # memory expires only when it carries its own 'ttl'.
                        Name           = 'memory'
                        PartitionKey   = '/userId'
                        MaxThroughput  = 1000
                        DefaultTtl     = -1
                        FullTextPolicy = @{
                            defaultLanguage = 'en-US'
                            fullTextPaths   = @(
                                @{ path = '/content'; language = 'en-US' }
                            )
                        }
                        VectorEmbeddings = @{
                            vectorEmbeddings = @(
                                @{
                                    path             = '/embedding'
                                    dataType         = 'float32'
                                    distanceFunction = 'cosine'
                                    dimensions       = 1536
                                }
                            )
                        }
                        IndexingPolicy = @{
                            indexingMode    = 'consistent'
                            automatic       = $true
                            includedPaths   = @(@{ path = '/*' })
                            excludedPaths   = @(
                                @{ path = '/"_etag"/?' }
                                @{ path = '/embedding/*' }
                            )
                            fullTextIndexes = @(@{ path = '/content' })
                            vectorIndexes   = @(@{ path = '/embedding'; type = 'quantizedFlat' })
                        }
                    }
                )
            }
        )
    }
    backup   = @{
        # Continuous backup can only be chosen when the account is created, and the
        # exercise deletes the container it restores, so this account stands alone too.
        Account   = @{
            Dedicated      = $true
            BackupPolicy   = 'Continuous'
            ContinuousTier = 'Continuous7Days'
        }
        Databases = @(
            @{
                Name       = 'cosmicworks'
                # Left empty on purpose. The exercise loads the catalog itself so that
                # the restore point it captures sits after a write it performed.
                Containers = @(
                    @{ Name = 'product'; PartitionKey = '/categoryId'; Throughput = 400 }
                )
            }
        )
    }
}

#endregion

#region Logging

# Appends one timestamped line to the run log. Never writes to the console.
function Write-Log {
    param([string]$Message)

    if (-not $script:LogPath) { return }
    "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message | Add-Content -LiteralPath $script:LogPath -Encoding utf8
}

# Renders an elapsed TimeSpan as a short string, for example '9m 42s'.
function Format-Duration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        return '{0}h {1}m {2}s' -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds
    }
    if ($Duration.TotalMinutes -ge 1) {
        return '{0}m {1}s' -f [int]$Duration.TotalMinutes, $Duration.Seconds
    }
    return '{0:0.0}s' -f $Duration.TotalSeconds
}

# Opens a log file for this run and records the parameters and environment that
# shaped it. Learners are asked to attach this file when reporting a failure.
function Initialize-Log {
    $script:StartTime = Get-Date

    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $directory = Join-Path $root 'logs'

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $script:LogPath = Join-Path $directory ('setup-{0:yyyyMMdd-HHmmss}.log' -f $script:StartTime)
    Write-Host "Logging to $script:LogPath" -ForegroundColor DarkGray

    Write-Log 'setup.ps1'
    Write-Log "Started        : $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "ResourceGroup  : $ResourceGroup"
    Write-Log "AccountName    : $(if ($AccountName) { $AccountName } else { '(generated)' })"
    Write-Log "NamePrefix     : $NamePrefix"
    Write-Log "LabProfile     : $LabProfile"
    Write-Log "Location       : $Location"
    Write-Log "Secondary      : $(if ($script:SecondLocation) { $script:SecondLocation } else { '(none)' })"
    Write-Log "SkipSeed       : $SkipSeed"
    Write-Log "PSVersion      : $($PSVersionTable.PSVersion)"
    Write-Log "OS             : $([System.Environment]::OSVersion.VersionString)"
}

# Reports progress to the learner and mirrors it into the log.
function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
    Write-Log "STEP $Message"
}

#endregion

#region Azure CLI

# Runs one Azure CLI command, records it in the log, and throws when it fails.
# Every CLI call in this script goes through here so the log stays complete.
function Invoke-Az {
    param([string[]]$Arguments)

    $command = "az $($Arguments -join ' ')"
    Write-Log "RUN  $command"

    # --only-show-errors drops CLI warnings that are noise to a learner, such as the
    # enable_pbe attribute warning az cosmosdb create emits.
    $arguments = @($Arguments) + '--only-show-errors'

    # Capture stderr to a file rather than merging it into stdout. Merging corrupts
    # every caller that parses the result as JSON or TSV.
    $errorFile = [System.IO.Path]::GetTempFileName()
    $previousPreference = $ErrorActionPreference

    try {
        # Some PowerShell 7 builds turn redirected native stderr into a terminating error.
        $ErrorActionPreference = 'Continue'
        $output = & az @arguments 2>$errorFile
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

# Fails early on the three things that break this script most often: an old
# PowerShell, an old or shadowed Azure CLI, and a missing sign-in.
function Assert-Prerequisites {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This script requires PowerShell 7 or later. You are running $($PSVersionTable.PSVersion). See https://learn.microsoft.com/powershell/scripting/install/installing-powershell."
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'The Azure CLI is not installed. See https://learn.microsoft.com/cli/azure/install-azure-cli.'
    }

    $azPaths = @(Get-Command az -All | ForEach-Object { $_.Source })
    Write-Log "az on PATH     : $($azPaths -join ' | ')"

    $version = & az version --output json 2>$null | ConvertFrom-Json
    Write-Log "az version     : $($version.'azure-cli')"

    $cliVersion = $null
    [void][version]::TryParse($version.'azure-cli', [ref]$cliVersion)

    if ($cliVersion -and $cliVersion -lt $MinimumCliVersion) {
        $message = "The Azure CLI is $cliVersion, but this script needs $MinimumCliVersion or later. See https://learn.microsoft.com/cli/azure/install-azure-cli."

        # A stale CLI winning a PATH race is the usual cause, so name the winner.
        if ($azPaths.Count -gt 1) {
            $message += " More than one 'az' is on PATH and this one wins: $($azPaths[0]). Remove it or reorder PATH, then open a new terminal."
        }

        throw $message
    }

    if ($azPaths.Count -gt 1) {
        Write-Log "NOTE more than one 'az' is on PATH. Using $($azPaths[0])."
    }

    $account = & az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "You are not signed in to the Azure CLI. Run 'az login' and try again."
    }

    Write-Step "Signed in as $($account.user.name) on subscription '$($account.name)'."

    if ($LabProfile -eq 'core' -and $Location -notin $ContainerCopyRegions) {
        Write-Warning "Region '$Location' does not support container copy jobs. The change feed exercise cannot complete its final task in this region."
    }
}

#endregion

#region Provisioning

# Finds a free account name by appending random characters to the prefix.
# Account names are globally unique across all of Azure, not just this subscription.
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

# Registers the resource providers and makes sure the resource group exists.
# A lab environment often supplies the group already, so an existing one is reused.
function Initialize-Subscription {
    $providers = @('Microsoft.DocumentDB') + @($Profiles[$LabProfile].Account.Providers | Where-Object { $_ })

    foreach ($provider in $providers) {
        Write-Step "Registering the $provider resource provider."
        Invoke-Az @('provider', 'register', '--namespace', $provider, '--wait') | Out-Null
    }

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

# Creates the account when it is missing and returns its document endpoint.
function New-LabAccount {
    $options = $Profiles[$LabProfile].Account

    $existing = & az cosmosdb show --name $AccountName --resource-group $ResourceGroup --output json 2>$null
    if ($existing) {
        $account = $existing | ConvertFrom-Json

        # Backup policy and capacity mode are fixed at creation, so a reused account
        # that was created for a different profile can't be corrected here.
        if ($options.BackupPolicy -and $account.backupPolicy.type -ne $options.BackupPolicy) {
            throw "Account '$AccountName' uses $($account.backupPolicy.type) backup, but the '$LabProfile' profile needs $($options.BackupPolicy) backup, which can only be chosen when the account is created. Use a different -NamePrefix or an empty resource group."
        }

        Write-Step "Account '$AccountName' already exists. Skipping creation."
        return $account.documentEndpoint
    }

    Write-Step "Creating account '$AccountName'. This takes 5-10 minutes."
    $arguments = @(
        'cosmosdb', 'create',
        '--name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--locations', "regionName=$Location", 'failoverPriority=0', 'isZoneRedundant=False'
    )

    if ($script:SecondLocation) {
        Write-Step "Adding '$($script:SecondLocation)' as a second region. Creating both at once is much faster than adding one later."
        $arguments += @('--locations', "regionName=$($script:SecondLocation)", 'failoverPriority=1', 'isZoneRedundant=False')
    }

    $arguments += @(
        '--default-consistency-level', 'Session',
        '--disable-local-auth', 'true'
    )

    if ($options.Serverless) { $arguments += @('--capabilities', 'EnableServerless') }
    # Vector search is an account capability, and it can't be turned off once it is on,
    # which is why the profile that needs it also creates an account of its own.
    foreach ($capability in @($options.Capabilities)) {
        if ($capability) { $arguments += @('--capabilities', $capability) }
    }
    if ($options.PublicNetworkAccess) { $arguments += @('--public-network-access', $options.PublicNetworkAccess) }
    if ($options.BackupPolicy) { $arguments += @('--backup-policy-type', $options.BackupPolicy) }
    if ($options.ContinuousTier) { $arguments += @('--continuous-tier', $options.ContinuousTier) }

    $created = Invoke-Az ($arguments + @('--output', 'json'))

    return ($created | ConvertFrom-Json).documentEndpoint
}

# Gives the signed-in user read and write access to data in the account.
# The account has key authentication disabled, so without this nothing can read or write.
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

# Creates a database when it is missing.
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

# Creates a container from a profile entry, using autoscale when the entry sets
# MaxThroughput and manual throughput otherwise.
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

    # Time to live has to be enabled on the container before an item's own 'ttl'
    # property does anything, so a profile that relies on per-item expiry sets this.
    if ($null -ne $Container.DefaultTtl) {
        $arguments += @('--ttl', $Container.DefaultTtl)
    }

    if ($Profiles[$LabProfile].Account.Serverless) {
        # Serverless containers take no throughput argument at all.
        $sizing = 'serverless'
    }
    elseif ($Container.MaxThroughput) {
        $arguments += @('--max-throughput', $Container.MaxThroughput)
        $sizing = "autoscale to $($Container.MaxThroughput) RU/s"
    }
    else {
        $arguments += @('--throughput', $Container.Throughput)
        $sizing = "$($Container.Throughput) RU/s manual"
    }

    # PowerShell strips the quotation marks out of an inline JSON argument before the
    # Azure CLI sees it, so every policy is written to a file and passed with the
    # documented '@<file>' convention instead.
    $policyFiles = @()
    foreach ($policy in @(
            @{ Key = 'IndexingPolicy'; Argument = '--idx' },
            @{ Key = 'VectorEmbeddings'; Argument = '--vector-embeddings' },
            @{ Key = 'FullTextPolicy'; Argument = '--full-text-policy' })) {

        if (-not $Container[$policy.Key]) { continue }

        $path = Join-Path ([IO.Path]::GetTempPath()) ('dp420-{0}-{1}.json' -f $Container.Name, $policy.Key)
        $Container[$policy.Key] | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
        $arguments += @($policy.Argument, "@$path")
        $policyFiles += $path
    }

    Write-Step "Creating container '$Database/$($Container.Name)' on $($Container.PartitionKey), $sizing."
    try {
        Invoke-Az $arguments | Out-Null
    }
    finally {
        $policyFiles | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
    }
}

#endregion

#region Seeding

# Gets a Microsoft Entra ID access token for this account's data plane.
function Get-CosmosToken {
    param([string]$Endpoint)

    # documentEndpoint carries an explicit ':443', but the token audience is the bare
    # host, which is what the Cosmos DB SDKs request. Leaving the port on produces a
    # token the service rejects with a 401.
    $resource = 'https://{0}' -f ([Uri]$Endpoint).Host
    return (Invoke-Az @('account', 'get-access-token', '--resource', $resource, '--query', 'accessToken', '--output', 'tsv')).Trim()
}

# Downloads a CosmicWorks dataset and upserts every item into the container.
# Writes go over the REST API because this script deliberately takes no SDK dependency:
# it runs before the learner has installed .NET or Python.
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
    $authorization = [uri]::EscapeDataString("type=aad&ver=1.0&sig=$token")
    $total = @($items).Count

    Write-Log "SEED POST $uri ($total items, partition key property '$partitionKeyProperty', concurrency $SeedConcurrency)"
    # Enough to diagnose a rejected header without writing the bearer token to disk.
    Write-Log "SEED Authorization prefix '$($authorization.Substring(0, 24))...' length $($authorization.Length)"

    $outcomes = $items | ForEach-Object -ThrottleLimit $SeedConcurrency -Parallel {
        $item = $_
        $uri = $using:uri
        $authorization = $using:authorization
        $partitionKeyProperty = $using:partitionKeyProperty

        # The header must be a JSON array. ConvertTo-Json unwraps a single-element
        # array, so build the brackets by hand and let it escape only the value.
        $partitionKeyHeader = '[' + ($item.$partitionKeyProperty | ConvertTo-Json -Compress) + ']'
        $body = [System.Text.Encoding]::UTF8.GetBytes(($item | ConvertTo-Json -Depth 20 -Compress))

        $maxAttempts = 6

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $headers = @{
                'Authorization'                = $authorization
                'x-ms-version'                 = '2018-12-31'
                'x-ms-date'                    = [DateTime]::UtcNow.ToString('r')
                'x-ms-documentdb-partitionkey' = $partitionKeyHeader
                'x-ms-documentdb-is-upsert'    = 'true'
            }

            try {
                Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
                [pscustomobject]@{ Id = $item.id; Status = 'ok'; Detail = $null; Retries = $attempt - 1 }
                break
            }
            catch {
                $response = $_.Exception.Response
                $status = if ($response) { [int]$response.StatusCode } else { 0 }

                # A raw REST client gets none of the automatic 429 handling the SDKs provide.
                if ($status -eq 429 -and $attempt -lt $maxAttempts) {
                    $waitMs = 1000
                    $values = $null
                    if ($response.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$values)) {
                        $waitMs = [int]($values | Select-Object -First 1)
                    }
                    Start-Sleep -Milliseconds ([Math]::Max($waitMs, 100))
                    continue
                }

                [pscustomobject]@{
                    Id      = $item.id
                    Status  = $status
                    Detail  = $_.ErrorDetails.Message
                    Retries = $attempt - 1
                }
                break
            }
        }
    }

    $written = @($outcomes | Where-Object { $_.Status -eq 'ok' }).Count
    $throttled = @($outcomes | Where-Object { $_.Retries -gt 0 }).Count
    $failures = @($outcomes | Where-Object { $_.Status -ne 'ok' })

    if ($throttled -gt 0) {
        Write-Log "SEED $throttled item(s) were retried after throttling (429). Consider a lower -SeedConcurrency."
    }

    if ($failures.Count -gt 0) {
        $first = $failures[0]
        Write-Log "SEED FAILED $($failures.Count) of $total. First: id '$($first.Id)' HTTP $($first.Status). $($first.Detail)"

        if ($first.Status -eq 401 -or $first.Status -eq 403) {
            throw "Authorization failed writing to $($Container.Name) (HTTP $($first.Status)). A new role assignment can take a few minutes to propagate. Wait, then re-run this script."
        }

        throw "Failed writing $($failures.Count) of $total items to $($Container.Name). The first failure was HTTP $($first.Status)."
    }

    Write-Log "SEED loaded $written items into $($Container.Name)."
    Write-Host "    Loaded $written items into $($Container.Name)." -ForegroundColor Green
}

#endregion

#region Main

if ($Profiles[$LabProfile].Account.RegionCount -eq 2) {
    $script:SecondLocation = if ($SecondaryLocation) { $SecondaryLocation.ToLowerInvariant() } else { $DefaultSecondaryLocation[$Location.ToLowerInvariant()] }

    if (-not $script:SecondLocation) {
        throw "The '$LabProfile' profile needs two regions and this script has no default second region for '$Location'. Pass -SecondaryLocation with an Azure region that supports Azure Cosmos DB."
    }

    if ($script:SecondLocation -eq $Location.ToLowerInvariant()) {
        throw "-SecondaryLocation must differ from -Location. Both are '$Location'."
    }
}

Initialize-Log

trap {
    $elapsed = Format-Duration ((Get-Date) - $script:StartTime)

    Write-Log "FAIL $($_.Exception.Message)"
    if ($_.ScriptStackTrace) { Write-Log $_.ScriptStackTrace }
    Write-Log "Failed after   : $elapsed"

    Write-Host ''
    Write-Host "Setup failed after $elapsed. Include this log file when you ask for help:" -ForegroundColor Red
    Write-Host "  $script:LogPath" -ForegroundColor Yellow
    break
}

Assert-Prerequisites

if ($Profiles[$LabProfile].Account.Dedicated) {
    Write-Warning "The '$LabProfile' profile creates a disposable account that its exercise reconfigures and then deletes. Run it against a resource group of its own, not the one holding your shared course account."
}

Initialize-Subscription

$accountCount = if ($Profiles[$LabProfile].Account.AccountCount) { $Profiles[$LabProfile].Account.AccountCount } else { 1 }

if ($AccountName) {
    if ($accountCount -gt 1) {
        throw "The '$LabProfile' profile creates $accountCount accounts, so it can't target a named account. Omit -AccountName and pass -NamePrefix instead."
    }

    if ($AccountName -notmatch '^[a-z0-9][a-z0-9-]{1,42}[a-z0-9]$') {
        throw "'$AccountName' isn't a valid Azure Cosmos DB account name. Use 3-44 lowercase letters, numbers, and hyphens."
    }

    $accountNames = @($AccountName)
}
else {
    # Re-use accounts this script created earlier. Without this, a re-run after a
    # mid-script failure generates fresh names and leaves extra billable accounts behind.
    $existing = @(& az cosmosdb list --resource-group $ResourceGroup `
            --query "[?starts_with(name, '$NamePrefix')].name" --output tsv 2>$null |
        Where-Object { $_ } | ForEach-Object { $_.Trim() } | Sort-Object)

    $accountNames = @($existing | Select-Object -First $accountCount)

    foreach ($name in $accountNames) {
        Write-Step "Reusing the existing account '$name' in '$ResourceGroup'."
    }

    while ($accountNames.Count -lt $accountCount) {
        $generated = New-AccountName -Prefix $NamePrefix
        Write-Step "Generated account name '$generated'."
        $accountNames += $generated
    }
}

$provisioned = @()
$databases = $Profiles[$LabProfile].Databases

foreach ($name in $accountNames) {
    # The provisioning and seeding functions read $AccountName from this scope.
    $AccountName = $name

    $endpoint = New-LabAccount

    if ($Profiles[$LabProfile].Account.GrantDataPlaneAccess -eq $false) {
        Write-Step 'This profile grants no data-plane role to the signed-in user. The exercise assigns scoped roles itself.'
    }
    else {
        Grant-DataPlaneAccess
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

    $provisioned += [pscustomobject]@{ Name = $name; Endpoint = $endpoint }
}

$endTime = Get-Date
$totalElapsed = Format-Duration ($endTime - $script:StartTime)

Write-Log "Finished       : $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "Total run time : $totalElapsed"

Write-Host ''
Write-Host "Setup complete. Record $(if ($provisioned.Count -gt 1) { 'these values' } else { 'these two values' })." -ForegroundColor Green
Write-Host ''
foreach ($account in $provisioned) {
    Write-Host "  Account name     : $($account.Name)" -ForegroundColor Yellow
    Write-Host "  Account endpoint : $($account.Endpoint)" -ForegroundColor Yellow
    Write-Host ''
}
Write-Host "  Resource group   : $ResourceGroup"
Write-Host "  Location         : $Location"
if ($script:SecondLocation) { Write-Host "  Second region    : $($script:SecondLocation)" }
Write-Host "  Lab profile      : $LabProfile"
Write-Host "  Started          : $($script:StartTime.ToString('HH:mm:ss'))"
Write-Host "  Finished         : $($endTime.ToString('HH:mm:ss'))"
Write-Host "  Total run time   : $totalElapsed"
Write-Host "  Log file         : $script:LogPath"
Write-Host ''
Write-Host 'Every exercise in this course asks for the account endpoint.'

#endregion

