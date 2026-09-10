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
               Serves the resources, SDK, operations, query, and change feed exercises.
    aitools  - The core catalog plus the five Agent Memory Toolkit containers in
               ai_memory. Requires two-stage search enrollment. Use EnableFoundry
               to provision the chat and embedding deployments for module 8.
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

.PARAMETER PreflightOnly
    Check the selected profile's regions and optional Foundry model capacity and
    quota without creating or changing Azure resources. Normal setup also runs
    these checks before provisioning. The checks do not reserve capacity.

.PARAMETER AccountOnly
    Create or locate the account without provisioning databases, roles, or data.
    Use this first for search, agentmemory, and aitools, then enroll features in the portal.

.PARAMETER SearchFeaturesReady
    Confirm that vector and full-text enrollment is complete in the portal.
    Requires AccountName so the second stage targets the enrolled account.

.PARAMETER SeedConcurrency
    How many seed writes to issue at once. Set to 1 to load serially when
    troubleshooting a seeding failure.

.PARAMETER EnableFoundry
    Deploy foundry.bicep in the same resource group. Creates a keyless Foundry
    resource, project, embedding deployment, optional chat deployment, and user role.
    Works during either setup stage. Without this switch, no Foundry operations run.

.PARAMETER EmbeddingOnly
    With EnableFoundry, omit the chat model for embedding-only exercises.

.PARAMETER FoundryLocation
    Region for the model deployments, independent of the Cosmos DB region.
    Defaults to eastus. Model availability and quota must permit the deployment.

.PARAMETER FoundryAccountName
    Optional existing or new Foundry resource name. Defaults to the Cosmos DB
    account name followed by -ai. Existing resources and deployments are not reset.

.PARAMETER FoundryProjectName
    Project to create or reuse in the Foundry resource. Defaults to dp420.

.PARAMETER EmbeddingModel
    Embedding model and deployment name. Defaults to text-embedding-3-small.

.PARAMETER EmbeddingModelVersion
    Embedding model version. Defaults to 1.

.PARAMETER ChatModel
    Chat model and deployment name. Defaults to gpt-5.4-mini.

.PARAMETER ChatModelVersion
    Chat model version. Defaults to 2026-03-17.

.PARAMETER EmbeddingDeploymentSku
    Pay-per-token embedding deployment type. Defaults to Standard.

.PARAMETER ChatDeploymentSku
    Pay-per-token chat deployment type. Defaults to GlobalStandard.

.PARAMETER EmbeddingCapacity
    Model-specific embedding capacity units. Defaults to 30.

.PARAMETER ChatCapacity
    Model-specific chat capacity units. Defaults to 30.

.NOTES
    Cosmos resources are declared in cosmos.bicep. Optional Foundry resources are
    declared in foundry.bicep. Both templates sit beside this script.

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

    [ValidateSet('core', 'modeling', 'security', 'backup', 'multiregion', 'indexing', 'monitoring', 'mirroring', 'fleet', 'search', 'agentmemory', 'aitools')]
    [string]$LabProfile = 'core',

    [string]$Location = 'westus2',

    [string]$SecondaryLocation,

    [ValidateRange(1, 64)]
    [int]$SeedConcurrency = 32,

    [switch]$SkipSeed,

    [switch]$PreflightOnly,

    [switch]$AccountOnly,

    [switch]$SearchFeaturesReady,

    [switch]$EnableFoundry,

    [switch]$EmbeddingOnly,

    [string]$FoundryLocation = 'eastus',

    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$')]
    [string]$FoundryAccountName,

    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,63}$')]
    [string]$FoundryProjectName = 'dp420',

    [ValidateSet('text-embedding-3-small', 'text-embedding-3-large')]
    [string]$EmbeddingModel = 'text-embedding-3-small',

    [ValidateNotNullOrEmpty()]
    [string]$EmbeddingModelVersion = '1',

    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]*$')]
    [string]$ChatModel = 'gpt-5.4-mini',

    [ValidateNotNullOrEmpty()]
    [string]$ChatModelVersion = '2026-03-17',

    [ValidateSet('Standard', 'GlobalStandard', 'DataZoneStandard')]
    [string]$EmbeddingDeploymentSku = 'Standard',

    [ValidateSet('Standard', 'GlobalStandard', 'DataZoneStandard')]
    [string]$ChatDeploymentSku = 'GlobalStandard',

    [ValidateRange(1, 1000)]
    [int]$EmbeddingCapacity = 30,

    [ValidateRange(1, 1000)]
    [int]$ChatCapacity = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Configuration

$DataRoot = 'https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data'

# The template lives beside this script, so a learner can run the script from anywhere.
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:TemplateFile = Join-Path $script:ScriptRoot 'cosmos.bicep'
$script:FoundryTemplateFile = Join-Path $script:ScriptRoot 'foundry.bicep'

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
            Providers            = @('Microsoft.ContainerInstance')
            RegionalResources    = @(@{ ProviderNamespace = 'Microsoft.ContainerInstance'; ResourceType = 'containerGroups' })
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
        Account = @{
            RegionalResources = @(@{ ProviderNamespace = 'Microsoft.OperationalInsights'; ResourceType = 'workspaces' })
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
        Account   = @{
            BackupPolicy        = 'Continuous'
            ContinuousTier      = 'Continuous7Days'
            PublicNetworkAccess = 'Enabled'
            RequireAllNetworks  = $true
            RequireSingleWriteLocation = $true
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
            AccountCount = 2
            RegionalResources = @(
                @{ ProviderNamespace = 'Microsoft.DocumentDB'; ResourceType = 'fleets' }
                @{ ProviderNamespace = 'Microsoft.Storage'; ResourceType = 'storageAccounts' }
            )
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
            Capabilities = @('EnableNoSQLVectorSearch', 'DeleteAllItemsByPartitionKey')
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

$Profiles.aitools = @{
    Account = @{ Capabilities = @('EnableNoSQLVectorSearch') }
    Databases = @($Profiles.core.Databases) + @(
        @{
            Name = 'ai_memory'
            Containers = @(
                foreach ($containerName in 'memories', 'memories_turns', 'memories_summaries') {
                    $indexingPolicy = @{
                        indexingMode = 'consistent'
                        automatic = $true
                        includedPaths = @(@{ path = '/*' })
                        excludedPaths = @(
                            @{ path = '/source_memory_ids/*' }
                            @{ path = '/supersedes_ids/*' }
                            @{ path = '/"_etag"/?' }
                        )
                        vectorIndexes = @(@{ path = '/embedding'; type = 'quantizedFlat' })
                        fullTextIndexes = @(@{ path = '/content' })
                    }
                    if ($containerName -eq 'memories_summaries') {
                        $indexingPolicy.compositeIndexes = ,@(
                            @{ path = '/user_id'; order = 'ascending' }
                            @{ path = '/thread_id'; order = 'ascending' }
                            @{ path = '/version'; order = 'descending' }
                        )
                    }
                    @{
                        Name = $containerName
                        PartitionKey = @('/user_id', '/thread_id')
                        MaxThroughput = 1000
                        DefaultTtl = if ($containerName -eq 'memories_turns') { 2592000 } else { -1 }
                        VectorEmbeddings = @{
                            vectorEmbeddings = @(@{
                                path = '/embedding'
                                dataType = 'float32'
                                dimensions = 1536
                                distanceFunction = 'cosine'
                            })
                        }
                        FullTextPolicy = @{
                            defaultLanguage = 'en-US'
                            fullTextPaths = @(@{ path = '/content'; language = 'en-US' })
                        }
                        IndexingPolicy = $indexingPolicy
                    }
                }
                @{ Name = 'counter'; PartitionKey = @('/user_id', '/thread_id'); MaxThroughput = 1000 }
                @{ Name = 'leases'; PartitionKey = '/id'; MaxThroughput = 1000 }
            )
        }
    )
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
    Write-Log "EnableFoundry  : $EnableFoundry"
    if ($EnableFoundry) {
        Write-Log "Foundry        : $FoundryAccountName / $FoundryProjectName in $FoundryLocation"
        Write-Log "Models         : $EmbeddingModel $EmbeddingModelVersion; chat enabled: $(-not $EmbeddingOnly)"
    }
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

    $sensitiveOutput = $Arguments.Count -ge 2 -and
        $Arguments[0] -eq 'account' -and $Arguments[1] -eq 'get-access-token'
    $command = "az $($Arguments -join ' ')"
    Write-Log "RUN  $command"

    # --only-show-errors drops CLI warnings that are noise to a learner, such as the
    # enable_pbe attribute warning az cosmosdb create emits.
    $arguments = @($Arguments) + '--only-show-errors'

    $azCommand = Get-Command az -ErrorAction Stop
    if ($IsWindows -and $azCommand.CommandType -eq 'Application' -and
        [IO.Path]::GetExtension($azCommand.Source) -in @('.cmd', '.bat')) {
        for ($argumentIndex = 0; $argumentIndex -lt $arguments.Count; $argumentIndex++) {
            if ($arguments[$argumentIndex] -match '^https?://[^"\r\n]*[&|<>()^][^"\r\n]*$') {
                $PSNativeCommandArgumentPassing = 'Legacy'
                $arguments[$argumentIndex] = '"' + $arguments[$argumentIndex] + '"'
            }
        }
    }

    # Capture stderr to a file rather than merging it into stdout. Merging corrupts
    # every caller that parses the result as JSON or TSV.
    $errorFile = [System.IO.Path]::GetTempFileName()
    $previousPreference = $ErrorActionPreference

    try {
        # Some PowerShell 7 builds turn redirected native stderr into a terminating error.
        $ErrorActionPreference = 'Continue'
        $output = & $azCommand @arguments 2>$errorFile
        $exitCode = $LASTEXITCODE
        $stderr = (Get-Content -LiteralPath $errorFile -Raw)
    }
    finally {
        $ErrorActionPreference = $previousPreference
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }

    Write-Log "EXIT $exitCode"
    if ($sensitiveOutput) {
        Write-Log 'OUT/ERR suppressed for token acquisition.'
    }
    elseif ($output) { Write-Log "OUT  $($output -join [Environment]::NewLine)" }

    if ($stderr -and -not $sensitiveOutput) {
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

    if (-not (Test-Path -LiteralPath $script:TemplateFile)) {
        throw "cosmos.bicep was not found beside this script at '$script:TemplateFile'. Both files ship together in Allfiles/Labs/Shared."
    }
    if ($EnableFoundry -and -not (Test-Path -LiteralPath $script:FoundryTemplateFile)) {
        throw "foundry.bicep was not found beside this script at '$script:FoundryTemplateFile'. Update the lab repository before using -EnableFoundry."
    }

    # The CLI installs its own copy of the Bicep compiler on first use. Doing it here
    # keeps the download out of the middle of a deployment.
    & az bicep version --only-show-errors 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Step 'Installing the Bicep CLI.'
        Invoke-Az @('bicep', 'install') | Out-Null
    }

}

function Assert-ResourceRegion {
    param(
        [string]$ProviderNamespace,
        [string]$ResourceType,
        [string[]]$Regions
    )

    $provider = Invoke-Az @('provider', 'show', '--namespace', $ProviderNamespace, '--output', 'json') | ConvertFrom-Json
    $resource = $provider.resourceTypes | Where-Object { $_.resourceType -eq $ResourceType } | Select-Object -First 1
    $supported = @($resource.locations | Where-Object { $_ } | ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() })
    if (-not $supported.Count) {
        throw "Azure did not return supported regions for '$ProviderNamespace/$ResourceType'. Check subscription access and rerun setup."
    }

    foreach ($region in $Regions) {
        if ($region -notin $supported) {
            throw "'$ProviderNamespace/$ResourceType' is not listed in region '$region'. Choose a supported region: $($supported -join ', ')."
        }
        Write-Step "Region '$region' supports '$ProviderNamespace/$ResourceType'."
    }
}

function Assert-FoundryAvailability {
    param([string[]]$AccountNames, [bool]$ResourceGroupExists)

    Assert-ResourceRegion -ProviderNamespace 'Microsoft.CognitiveServices' -ResourceType 'accounts' -Regions @($FoundryLocation)
    $foundryAccounts = @()
    if ($ResourceGroupExists) {
        $foundryAccounts = @(Invoke-Az @('cognitiveservices', 'account', 'list', '--resource-group', $ResourceGroup, '--output', 'json') | ConvertFrom-Json)
    }
    $requests = @()
    $plannedAccounts = @{}
    foreach ($cosmosName in $AccountNames) {
        $values = Get-FoundryDeploymentParameters -PrincipalId '' -CosmosAccountName $cosmosName -Accounts $foundryAccounts
        $name = $values.accountName.value
        if ($plannedAccounts.ContainsKey($name)) { continue }
        $plannedAccounts[$name] = $true
        $requests += [pscustomobject]@{ Name = $EmbeddingModel; Version = $EmbeddingModelVersion; Sku = $EmbeddingDeploymentSku; Capacity = $EmbeddingCapacity; CapacityOption = '-EmbeddingCapacity'; Create = $values.deployEmbedding.value }
        if (-not $EmbeddingOnly) {
            $requests += [pscustomobject]@{ Name = $ChatModel; Version = $ChatModelVersion; Sku = $ChatDeploymentSku; Capacity = $ChatCapacity; CapacityOption = '-ChatCapacity'; Create = $values.deployChat.value }
        }
    }
    if (-not $requests.Count) {
        throw 'No Foundry deployment targets were selected for preflight.'
    }

    $models = @(Invoke-Az @('cognitiveservices', 'model', 'list', '--location', $FoundryLocation, '--output', 'json') | ConvertFrom-Json)
    $usages = @()
    $subscriptionId = ''
    if ($requests.Create -contains $true) {
        $usages = @(Invoke-Az @('cognitiveservices', 'usage', 'list', '--location', $FoundryLocation, '--output', 'json') | ConvertFrom-Json)
        if (-not $usages.Count) {
            throw "Azure returned no quota records for '$FoundryLocation'. Preflight cannot confirm deployment quota. Check Microsoft.CognitiveServices registration and subscription-level quota-read access, such as Cognitive Services Usages Reader. Resource-group permissions alone do not provide subscription quota visibility."
        }
        $subscriptionId = (Invoke-Az @('account', 'show', '--query', 'id', '--output', 'tsv')).Trim()
        if (-not $subscriptionId) { throw 'Azure did not return the current subscription ID for capacity checks.' }
    }
    $requiredQuota = @{}
    $capacityCache = @{}

    foreach ($group in $requests | Group-Object Name, Version, Sku) {
        $request = $group.Group[0]
        $newDeployments = @($group.Group | Where-Object { $_.Create })
        $needed = [int](($newDeployments | Measure-Object -Property Capacity -Sum).Sum)
        $matchingModels = @($models | Where-Object {
            $_.model.format -eq 'OpenAI' -and $_.model.name -eq $request.Name -and $_.model.version -eq $request.Version
        })
        $sku = $matchingModels.model.skus | Where-Object { $_.name -eq $request.Sku } | Select-Object -First 1
        if (-not $matchingModels.Count -or -not $sku) {
            throw "Foundry region '$FoundryLocation' does not list '$($request.Name)' version '$($request.Version)' on '$($request.Sku)'. Change -FoundryLocation or select a supported model/version/deployment type before rerunning."
        }
        $model = $matchingModels[0].model
        if ($model.lifecycleStatus -in @('Deprecated', 'Retired')) {
            throw "Model '$($request.Name)' version '$($request.Version)' is retired. Select a supported model version."
        }
        foreach ($retirement in @($model.deprecation.inference, $sku.deprecationDate) | Where-Object { $_ }) {
            if ([DateTimeOffset]::Parse($retirement) -le [DateTimeOffset]::UtcNow) {
                throw "Model '$($request.Name)' version '$($request.Version)' on '$($request.Sku)' is past its published retirement date."
            }
        }
        if ($needed -gt 0 -and $model.lifecycleStatus -eq 'Deprecating') {
            throw "Model '$($request.Name)' version '$($request.Version)' is restricted to existing customers. New-deployment access cannot be confirmed by this preflight. Select a generally available model or reuse an existing matching deployment."
        }
        if ($needed -eq 0) {
            Write-Step "Model '$($request.Name)' version '$($request.Version)' already has a matching deployment. No additional quota or capacity is needed."
            continue
        }

        $limits = $sku.capacity
        foreach ($deployment in $newDeployments) {
            $capacity = $deployment.Capacity
            $invalid = ($null -ne $limits.minimum -and $capacity -lt $limits.minimum) -or
                ($null -ne $limits.maximum -and $capacity -gt $limits.maximum) -or
                ($limits.step -gt 0 -and ($capacity - [int]$limits.minimum) % $limits.step -ne 0) -or
                (@($limits.allowedValues).Count -gt 0 -and $limits.allowedValues -and $capacity -notin $limits.allowedValues)
            if ($invalid) {
                throw "Capacity $capacity is not supported for '$($request.Name)' on '$($request.Sku)' in '$FoundryLocation'. Check $($request.CapacityOption): minimum=$($limits.minimum), maximum=$($limits.maximum), step=$($limits.step), allowed=$($limits.allowedValues -join ',')."
            }
        }
        if (-not $sku.usageName) {
            throw "Azure did not return a quota identifier for '$($request.Name)' on '$($request.Sku)'. Quota cannot be verified; update the Azure CLI or check subscription access."
        }
        $requiredQuota[$sku.usageName] += $needed

        $cacheKey = "$($request.Name)/$($request.Version)"
        if (-not $capacityCache.ContainsKey($cacheKey)) {
            $modelName = [uri]::EscapeDataString($request.Name)
            $modelVersion = [uri]::EscapeDataString($request.Version)
            $url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/modelCapacities?api-version=2024-10-01&modelFormat=OpenAI&modelName=$modelName&modelVersion=$modelVersion"
            $entries = @()
            while ($url) {
                $page = Invoke-Az @('rest', '--method', 'GET', '--url', $url, '--output', 'json') | ConvertFrom-Json
                $entries += @($page.value | Where-Object { $_ })
                $url = $page.nextLink
            }
            $capacityCache[$cacheKey] = $entries
        }
        if (-not $capacityCache[$cacheKey].Count) {
            throw "Azure returned no capacity records for '$($request.Name)' version '$($request.Version)'. Preflight cannot confirm capacity for '$($request.Sku)' in '$FoundryLocation'. An empty response does not report a capacity shortage. Check Microsoft.CognitiveServices registration and model access for the selected subscription before rerunning."
        }
        $available = $capacityCache[$cacheKey] | Where-Object {
            ($_.location -replace '\s', '') -eq $FoundryLocation -and
            $_.properties.skuName -eq $request.Sku -and
            $_.properties.model.name -eq $request.Name -and $_.properties.model.version -eq $request.Version
        } | Select-Object -First 1
        if (-not $available -or $null -eq $available.properties.availableCapacity -or $available.properties.availableCapacity -lt 0) {
            throw "Azure did not return usable capacity information for '$($request.Name)' version '$($request.Version)' on '$($request.Sku)' in '$FoundryLocation'. Preflight cannot confirm capacity. Check model access and capacity information for the selected subscription before rerunning."
        }
        if ($available.properties.availableCapacity -lt $needed) {
            $alternatives = @($capacityCache[$cacheKey] | Where-Object {
                $_.properties.skuName -eq $request.Sku -and $_.properties.availableCapacity -ge $needed
            } | ForEach-Object { $_.location } | Sort-Object -Unique)
            throw "Insufficient reported capacity for '$($request.Name)' version '$($request.Version)' on '$($request.Sku)' in '$FoundryLocation': need $needed, reported '$($available.properties.availableCapacity)'. Check -FoundryLocation and $($request.CapacityOption). Other reported regions to evaluate: $($alternatives -join ', ')."
        }
        Write-Step "Foundry lists '$($request.Name)' version '$($request.Version)' on '$($request.Sku)' in '$FoundryLocation' with capacity for $needed additional units."
    }

    foreach ($quotaName in $requiredQuota.Keys) {
        $usage = $usages | Where-Object { $_.name.value -eq $quotaName } | Select-Object -First 1
        if (-not $usage -or $null -eq $usage.limit -or $null -eq $usage.currentValue -or $usage.limit -lt 0 -or $usage.currentValue -lt 0) {
            throw "Azure did not return usable quota information for '$quotaName' in '$FoundryLocation'. Check subscription quota access before rerunning."
        }
        $remaining = $usage.limit - $usage.currentValue
        if ($remaining -lt $requiredQuota[$quotaName]) {
            throw "Insufficient Foundry quota for '$quotaName' in '$FoundryLocation': need $($requiredQuota[$quotaName]) additional capacity units; $remaining remain ($($usage.currentValue) used of $($usage.limit)). Reduce the requested capacity, request quota, or choose another -FoundryLocation."
        }
        Write-Step "Quota '$quotaName': $remaining units remain; setup needs $($requiredQuota[$quotaName])."
    }
}

function Assert-LabAvailability {
    param([string[]]$AccountNames, [object[]]$ExistingAccounts, [bool]$ResourceGroupExists)

    Write-Step "Checking regions and optional model availability for the '$LabProfile' profile before provisioning."
    try {
        $regionChecks = @{}
        $primaryRegions = @()
        foreach ($name in $AccountNames) {
            $existing = $ExistingAccounts | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if ($existing) {
                $locations = @($existing.locations | Sort-Object failoverPriority)
                if (-not $locations.Count) { throw "Azure did not return regions for existing Cosmos DB account '$name'." }
                foreach ($region in $locations.locationName) {
                    $regionName = ($region -replace '\s', '').ToLowerInvariant()
                    if (-not $regionChecks.ContainsKey($regionName)) { $regionChecks[$regionName] = $false }
                }
                $primaryRegions += ($locations[0].locationName -replace '\s', '').ToLowerInvariant()
            }
            else {
                if ($SearchFeaturesReady) { throw "Enrolled account '$name' was not found. Check -AccountName and -ResourceGroup; setup does not create a replacement for stage two." }
                $regionChecks[$Location] = $true
                $primaryRegions += $Location
                if ($script:SecondLocation) { $regionChecks[$script:SecondLocation] = $true }
            }
        }
        $locations = @(Invoke-Az @('cosmosdb', 'locations', 'list', '--output', 'json') | ConvertFrom-Json)
        foreach ($region in $regionChecks.Keys) {
            $metadata = $locations | Where-Object { ($_.name -replace '\s', '') -eq $region } | Select-Object -First 1
            if (-not $metadata -or $metadata.properties.status -ne 'Online') {
                throw "Cosmos DB region '$region' is not listed as Online for this subscription. Choose another -Location or -SecondaryLocation."
            }
            if ($regionChecks[$region] -and $metadata.properties.isSubscriptionRegionAccessAllowedForRegular -ne $true) {
                throw "This subscription does not report access to create the lab's non-zone-redundant Cosmos DB account in '$region'. Choose another region or request regional access."
            }
            Write-Step "Cosmos DB region '$region' passed the published availability check."
        }
        foreach ($region in $primaryRegions | Sort-Object -Unique) {
            if ($LabProfile -eq 'core' -and $region -notin $ContainerCopyRegions) {
                throw "The shared core account also serves the change feed exercise, whose container copy job is not supported in '$region'. Choose a documented copy-job region, such as eastus or westus2."
            }
        }
        foreach ($resource in @($Profiles[$LabProfile].Account.RegionalResources) | Where-Object { $_ }) {
            Assert-ResourceRegion -ProviderNamespace $resource.ProviderNamespace -ResourceType $resource.ResourceType -Regions @($Location)
        }
        if ($EnableFoundry) {
            Assert-FoundryAvailability -AccountNames $AccountNames -ResourceGroupExists $ResourceGroupExists
        }
        Write-Step 'Availability preflight passed. Capacity is not reserved; Azure policies, permissions, and feature enrollment can still affect deployment.'
    }
    catch {
        throw "Availability preflight failed before lab resources were created or changed. $($_.Exception.Message)"
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

# Registers required resource providers before querying their service APIs.
function Initialize-ResourceProviders {
    param([switch]$CheckOnly)

    $providers = @('Microsoft.DocumentDB') + @($Profiles[$LabProfile].Account.Providers | Where-Object { $_ })
    if ($EnableFoundry) { $providers += 'Microsoft.CognitiveServices' }

    foreach ($provider in $providers | Select-Object -Unique) {
        $metadata = Invoke-Az @('provider', 'show', '--namespace', $provider, '--output', 'json') | ConvertFrom-Json
        $registrationState = [string]$metadata.registrationState
        if (-not $registrationState) {
            throw "Azure did not return a registration state for '$provider'. Check subscription read access before rerunning setup."
        }
        Write-Step "Resource provider '$provider': $registrationState."
        if ($registrationState -in @('Registered', 'Registering')) { continue }
        if ($registrationState -ne 'NotRegistered') {
            throw "Resource provider '$provider' is '$registrationState'. Resolve this registration state before rerunning setup."
        }
        if ($CheckOnly) {
            throw "Resource provider '$provider' is not registered for this subscription. -PreflightOnly does not change provider registrations. Register the provider for the lab subscription, then rerun preflight."
        }

        Write-Step "Registering the $provider resource provider."
        try {
            Invoke-Az @('provider', 'register', '--namespace', $provider, '--wait') | Out-Null
        }
        catch {
            throw "Could not register '$provider'. Registration requires the provider's register/action permission at subscription scope. Ask your subscription administrator or lab provider to register it. $($_.Exception.Message)"
        }
        $metadata = Invoke-Az @('provider', 'show', '--namespace', $provider, '--output', 'json') | ConvertFrom-Json
        if ($metadata.registrationState -notin @('Registered', 'Registering')) {
            throw "Resource provider '$provider' did not complete registration. Reported state: '$($metadata.registrationState)'. No lab resources were created."
        }
        Write-Step "Resource provider '$provider': $($metadata.registrationState)."
    }
}

# A lab environment often supplies the group already, so an existing one is reused.
function Initialize-Subscription {
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

# Returns an existing account without changing its configuration.
function Get-LabAccount {
    $options = $Profiles[$LabProfile].Account

    $existing = & az cosmosdb show --name $AccountName --resource-group $ResourceGroup --output json 2>$null

    if (-not $existing) {
        if ($SearchFeaturesReady) {
            throw "Enrolled account '$AccountName' was not found. Check -AccountName and -ResourceGroup; this run does not create a replacement account."
        }

        return $null
    }

    $account = $existing | ConvertFrom-Json

    if ($options.BackupPolicy -and $account.backupPolicy.type -ne $options.BackupPolicy) {
        throw "Account '$AccountName' uses $($account.backupPolicy.type) backup, but the '$LabProfile' profile needs $($options.BackupPolicy) backup. This script does not migrate backup mode. Use a dedicated lab account or complete a supported migration separately."
    }

    if ($options.RequireAllNetworks -and (
        $account.publicNetworkAccess -ne 'Enabled' -or
        @($account.ipRules | Where-Object { $_ }).Count -gt 0 -or
        $account.isVirtualNetworkFilterEnabled
    )) {
        throw "The '$LabProfile' lab requires public network access for all networks. Existing network restrictions on '$AccountName' are not changed. Use a dedicated lab account, or configure Fabric private-network access separately."
    }

    if ($options.RequireSingleWriteLocation -and $account.enableMultipleWriteLocations) {
        throw "The '$LabProfile' lab requires a single write region. Existing write-region settings on '$AccountName' are not changed. Use a dedicated lab account."
    }

    return $account
}

# Flattens the profile's database and container tables into the shape cosmos.bicep
# takes. Every optional container setting is resolved here rather than in the template,
# so the template needs no knowledge of any lab.
#
# Containers that already exist are left out. Provisioning is additive, and several
# exercises change a container's own settings, so redeploying a definition the learner
# has since edited would quietly undo their work.
function Get-DeploymentContainers {
    param([bool]$AccountExists)

    $containers = @()

    foreach ($database in @($Profiles[$LabProfile].Databases)) {
        $existing = @()

        if ($AccountExists) {
            $existing = @(& az cosmosdb sql container list `
                    --account-name $AccountName --resource-group $ResourceGroup `
                    --database-name $database.Name --query '[].name' --output tsv 2>$null |
                Where-Object { $_ } | ForEach-Object { $_.Trim() })
        }

        foreach ($container in @($database.Containers)) {
            if ($container.Name -in $existing) {
                Write-Step "Container '$($database.Name)/$($container.Name)' already exists. Leaving it as it is."
                continue
            }

            $resourceProperties = [ordered]@{}

            # Time to live has to be enabled on the container before an item's own 'ttl'
            # property does anything, so a profile that relies on per-item expiry sets this.
            if ($null -ne $container.DefaultTtl) { $resourceProperties['defaultTtl'] = $container.DefaultTtl }
            if ($container.IndexingPolicy) { $resourceProperties['indexingPolicy'] = $container.IndexingPolicy }
            if ($container.VectorEmbeddings) { $resourceProperties['vectorEmbeddingPolicy'] = $container.VectorEmbeddings }
            if ($container.FullTextPolicy) { $resourceProperties['fullTextPolicy'] = $container.FullTextPolicy }

            # A profile may give PartitionKey as one path or as a list of up to three,
            # which is what a hierarchical partition key needs.
            $paths = @($container.PartitionKey)

            $containers += [ordered]@{
                databaseName       = $database.Name
                name               = $container.Name
                partitionKeyPaths  = $paths
                partitionKeyKind   = if ($paths.Count -gt 1) { 'MultiHash' } else { 'Hash' }
                throughput         = if ($container.Throughput) { [int]$container.Throughput } else { 0 }
                maxThroughput      = if ($container.MaxThroughput) { [int]$container.MaxThroughput } else { 0 }
                resourceProperties = $resourceProperties
            }
        }
    }

    return $containers
}

# Deploys the account, every database, every container, and the data-plane role
# assignment in one operation. Sibling resources in a template carry no dependency on
# each other, so Azure creates all of them at once instead of one after another.
function Invoke-LabDeployment {
    param(
        [bool]$DeployAccount,
        [string]$PrincipalId
    )

    $options = $Profiles[$LabProfile].Account

    $databaseNames = @()
    $containers = @()

    # -AccountOnly stops after the account, which is stage one of the search and
    # agentmemory profiles. An empty array creates nothing, so the same template serves
    # both stages.
    if (-not $AccountOnly) {
        $databaseNames = @(@($Profiles[$LabProfile].Databases) | ForEach-Object { $_.Name })
        $containers = Get-DeploymentContainers -AccountExists (-not $DeployAccount)
    }

    $values = [ordered]@{
        accountName          = @{ value = $AccountName }
        location             = @{ value = $Location }
        secondaryLocation    = @{ value = if ($script:SecondLocation) { $script:SecondLocation } else { '' } }
        deployAccount        = @{ value = $DeployAccount }
        serverless           = @{ value = [bool]$options.Serverless }
        capabilities         = @{ value = @(@($options.Capabilities) | Where-Object { $_ }) }
        publicNetworkAccess  = @{ value = if ($options.PublicNetworkAccess) { (Get-Culture).TextInfo.ToTitleCase($options.PublicNetworkAccess.ToLowerInvariant()) } else { 'Enabled' } }
        backupPolicyType     = @{ value = if ($options.BackupPolicy) { $options.BackupPolicy } else { 'Periodic' } }
        continuousTier       = @{ value = if ($options.ContinuousTier) { $options.ContinuousTier } else { 'Continuous7Days' } }
        dataPlanePrincipalId = @{ value = $PrincipalId }
        databaseNames        = @{ value = $databaseNames }
        containers           = @{ value = $containers }
    }

    $parameters = [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters     = $values
    }

    $parameterFile = Join-Path ([IO.Path]::GetTempPath()) ('dp420-{0}-{1}.parameters.json' -f $AccountName, [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $parameters | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $parameterFile -Encoding utf8

    $summary = if ($AccountOnly) {
        'the account only'
    }
    else {
        '{0} database(s) and {1} container(s)' -f $databaseNames.Count, $containers.Count
    }

    if ($DeployAccount) {
        Write-Step "Deploying account '$AccountName' and $summary. Creating the account takes 5-10 minutes; everything inside it is created at the same time."
    }
    else {
        Write-Step "Account '$AccountName' already exists. Deploying $summary into it."
    }

    # A deployment name has to be unique within the resource group, and the fleet
    # profile deploys twice into the same one.
    $deploymentName = 'dp420-{0}-{1}' -f $AccountName, (Get-Date -Format 'yyyyMMdd-HHmmss')

    try {
        Invoke-Az @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroup,
            '--name', $deploymentName,
            '--template-file', $script:TemplateFile,
            '--parameters', "@$parameterFile",
            '--output', 'none'
        ) | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
    }

    return (Invoke-Az @(
            'cosmosdb', 'show',
            '--name', $AccountName,
            '--resource-group', $ResourceGroup,
            '--query', 'documentEndpoint',
            '--output', 'tsv'
        )).Trim()
}

function Get-FoundryDeploymentParameters {
    param(
        [string]$PrincipalId,
        [string]$CosmosAccountName = $AccountName,
        [AllowEmptyCollection()][object[]]$Accounts
    )

    $name = if ($FoundryAccountName) { $FoundryAccountName } else { "$CosmosAccountName-ai" }
    $foundryAccounts = if ($PSBoundParameters.ContainsKey('Accounts')) { $Accounts } else {
        Invoke-Az @('cognitiveservices', 'account', 'list', '--resource-group', $ResourceGroup, '--output', 'json') | ConvertFrom-Json
    }
    $existingAccount = $foundryAccounts | Where-Object name -eq $name | Select-Object -First 1
    $existingDeployments = @()
    $existingProject = $null
    $existingRole = $null

    if ($existingAccount) {
        if ($existingAccount.kind -ne 'AIServices' -or -not $existingAccount.properties.allowProjectManagement -or
            $existingAccount.properties.disableLocalAuth -ne $true) {
            throw "Foundry resource '$name' must be an AIServices resource with project management enabled and key authentication disabled. It was not changed. Choose another -FoundryAccountName."
        }
        if (($existingAccount.location -replace ' ', '') -ne ($FoundryLocation -replace ' ', '')) {
            throw "Foundry resource '$name' is in '$($existingAccount.location)'. Rerun with that -FoundryLocation or choose a different -FoundryAccountName."
        }
        if ($existingAccount.properties.provisioningState -ne 'Succeeded') {
            throw "Foundry resource '$name' is not ready: $($existingAccount.properties.provisioningState). Resolve its provisioning failure or wait for the active operation before rerunning."
        }
        $existingDeployments = @(Invoke-Az @('cognitiveservices', 'account', 'deployment', 'list', '--name', $name, '--resource-group', $ResourceGroup, '--output', 'json') | ConvertFrom-Json)
        $projects = Invoke-Az @('rest', '--method', 'GET', '--url', "https://management.azure.com$($existingAccount.id)/projects?api-version=2025-06-01", '--output', 'json') | ConvertFrom-Json
        $existingProject = $projects.value | Where-Object { ($_.name -split '/')[-1] -eq $FoundryProjectName } | Select-Object -First 1
        $roles = Invoke-Az @('role', 'assignment', 'list', '--scope', $existingAccount.id, '--output', 'json') | ConvertFrom-Json
        $existingRole = $roles | Where-Object {
            $_.principalId -eq $PrincipalId -and $_.roleDefinitionId -like '*/53ca6127-db72-4b80-b1b0-d745d6d5456d'
        } | Select-Object -First 1
    }

    $values = [ordered]@{
        accountName             = @{ value = $name }
        location                = @{ value = $FoundryLocation }
        projectName             = @{ value = $FoundryProjectName }
        principalId             = @{ value = $PrincipalId }
        deployAccount           = @{ value = -not [bool]$existingAccount }
        deployProject           = @{ value = -not [bool]$existingProject }
        deployRoleAssignment    = @{ value = -not [bool]$existingRole }
        deployEmbedding         = @{ value = $true }
        deployChat              = @{ value = -not $EmbeddingOnly }
        embeddingModel          = @{ value = $EmbeddingModel }
        embeddingModelVersion   = @{ value = $EmbeddingModelVersion }
        embeddingDeploymentName = @{ value = $EmbeddingModel }
        embeddingDeploymentSku  = @{ value = $EmbeddingDeploymentSku }
        embeddingCapacity       = @{ value = $EmbeddingCapacity }
        chatModel               = @{ value = $ChatModel }
        chatModelVersion        = @{ value = $ChatModelVersion }
        chatDeploymentName      = @{ value = $ChatModel }
        chatDeploymentSku       = @{ value = $ChatDeploymentSku }
        chatCapacity            = @{ value = $ChatCapacity }
    }

    $requestedModels = @(@{ Name = $EmbeddingModel; Version = $EmbeddingModelVersion; Sku = $EmbeddingDeploymentSku; Flag = 'deployEmbedding' })
    if (-not $EmbeddingOnly) {
        $requestedModels += @{ Name = $ChatModel; Version = $ChatModelVersion; Sku = $ChatDeploymentSku; Flag = 'deployChat' }
    }
    foreach ($model in $requestedModels) {
        $existing = $existingDeployments | Where-Object name -eq $model.Name | Select-Object -First 1
        if (-not $existing) { continue }
        if ($existing.properties.model.name -ne $model.Name -or $existing.properties.model.version -ne $model.Version -or
            $existing.sku.name -ne $model.Sku) {
            throw "Existing deployment '$($model.Name)' in '$name' does not match the requested model version or deployment type. It was not changed. Check the deployment or use another -FoundryAccountName."
        }
        if ($existing.properties.provisioningState -in @('Failed', 'Canceled')) {
            Write-Step "Retrying model deployment '$($model.Name)' after its previous failure."
            continue
        }
        if ($existing.properties.provisioningState -ne 'Succeeded') {
            throw "Model deployment '$($model.Name)' is '$($existing.properties.provisioningState)'. Wait for that operation to finish before rerunning setup."
        }
        $values[$model.Flag].value = $false
        Write-Step "Reusing model deployment '$($model.Name)' without changing its capacity."
    }

    return $values
}

function Invoke-FoundryDeployment {
    param([string]$PrincipalId)

    $values = Get-FoundryDeploymentParameters -PrincipalId $PrincipalId
    $name = $values.accountName.value
    $parameters = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $values
    }
    $parameterFile = Join-Path ([IO.Path]::GetTempPath()) ('dp420-foundry-{0}.parameters.json' -f [Guid]::NewGuid().ToString('N'))
    $parameters | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding utf8
    $deploymentName = "dp420-foundry-$AccountName"
    Write-Step "Preparing Foundry resource '$name' in $FoundryLocation."
    try {
        Invoke-Az @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroup,
            '--name', $deploymentName,
            '--template-file', $script:FoundryTemplateFile,
            '--parameters', "@$parameterFile",
            '--mode', 'Incremental',
            '--output', 'none'
        ) | Out-Null
    }
    catch {
        throw "Foundry setup failed. Check model availability, quota in '$FoundryLocation', and role-assignment permission. Rerun against Cosmos account '$AccountName'; do not delete it to retry. $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
    }

    $resource = Invoke-Az @('cognitiveservices', 'account', 'show', '--name', $name, '--resource-group', $ResourceGroup, '--output', 'json') | ConvertFrom-Json
    if ($resource.properties.provisioningState -ne 'Succeeded') {
        throw "Foundry resource '$name' is not ready after deployment: $($resource.properties.provisioningState)."
    }
    $subdomain = $resource.properties.customSubDomainName
    if (-not $subdomain) { throw "Foundry resource '$name' did not return a custom subdomain." }
    $settings = [pscustomobject]@{
        CosmosAccountName = $AccountName
        ResourceGroup = $ResourceGroup
        FoundryAccountName = $name
        FoundryResourceId = $resource.id
        FoundryLocation = $resource.location
        FoundryProjectName = $FoundryProjectName
        OpenAiEndpoint = "https://$subdomain.openai.azure.com/"
        ProjectEndpoint = "https://$subdomain.services.ai.azure.com/api/projects/$FoundryProjectName"
        EmbeddingDeployment = $EmbeddingModel
        EmbeddingModelVersion = $EmbeddingModelVersion
        EmbeddingDimensions = 1536
        ChatDeployment = if ($EmbeddingOnly) { '' } else { $ChatModel }
        ChatModelVersion = if ($EmbeddingOnly) { '' } else { $ChatModelVersion }
    }
    $settingsFile = Join-Path $script:ScriptRoot "logs/foundry-$AccountName.json"
    $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding utf8
    Write-Log "Foundry settings: $settingsFile"
    return $settings
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

# Loads every dataset the profile needs, in one pass over every container at once.
# Writes go over the REST API because this script deliberately takes no SDK dependency:
# it runs before the learner has installed .NET or Python. A single HttpClient is shared
# by every write, so the connection and its TLS handshake are paid for once rather than
# once per item, and the work list is flat, so a small container never waits behind a
# large one.
function Add-SeedData {
    param(
        [string]$Endpoint,
        [array]$Databases
    )

    $targets = @(
        foreach ($database in $Databases) {
            foreach ($container in @($database.Containers)) {
                if (-not $container.Seed) { continue }

                [pscustomobject]@{
                    Database  = $database.Name
                    Container = $container.Name
                    Seed      = $container.Seed
                    KeyPath   = $container.PartitionKey.TrimStart('/')
                }
            }
        }
    )

    if ($targets.Count -eq 0) {
        Write-Step 'This profile seeds no data.'
        return
    }

    Write-Step "Downloading $($targets.Count) dataset(s)."
    $datasets = $targets | ForEach-Object -ThrottleLimit 8 -Parallel {
        # Invoke-RestMethod writes a JSON array to the pipeline as one object rather
        # than unrolling it, so wrapping the call in @() nests the whole dataset inside
        # a single-element array. Assign it and let the property hold the array itself.
        $items = Invoke-RestMethod -Uri $_.Seed -Method Get

        [pscustomobject]@{
            Target = $_
            Items  = $items
        }
    }

    $work = @(
        foreach ($dataset in $datasets) {
            $uri = "$($Endpoint.TrimEnd('/'))/dbs/$($dataset.Target.Database)/colls/$($dataset.Target.Container)/docs"

            
            foreach ($item in $dataset.Items) {
                [pscustomobject]@{
                    Container = $dataset.Target.Container
                    Uri       = $uri
                    # The header must be a JSON array. ConvertTo-Json unwraps a
                    # single-element array, so build the brackets by hand and let it
                    # escape only the value.
                    Key       = '[' + ($item.($dataset.Target.KeyPath) | ConvertTo-Json -Compress) + ']'
                    Body      = $item | ConvertTo-Json -Depth 20 -Compress
                }
            }
        }
    )

    $token = Get-CosmosToken -Endpoint $Endpoint
    $authorization = [uri]::EscapeDataString("type=aad&ver=1.0&sig=$token")

    Write-Step "Writing $($work.Count) items across $($targets.Count) container(s), $SeedConcurrency at a time."
    Write-Log "SEED $($work.Count) items, concurrency $SeedConcurrency"
    # Enough to diagnose a rejected header without writing the bearer token to disk.
    Write-Log "SEED Authorization prefix '$($authorization.Substring(0, 24))...' length $($authorization.Length)"

    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(100)

    try {
        $outcomes = $work | ForEach-Object -ThrottleLimit $SeedConcurrency -Parallel {
            $unit = $_
            $client = $using:client
            $authorization = $using:authorization

            $maxAttempts = 6

            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $unit.Uri)
                $request.Content = [System.Net.Http.StringContent]::new($unit.Body, [System.Text.Encoding]::UTF8, 'application/json')
                $request.Headers.TryAddWithoutValidation('Authorization', $authorization) | Out-Null
                $request.Headers.TryAddWithoutValidation('x-ms-version', '2018-12-31') | Out-Null
                $request.Headers.TryAddWithoutValidation('x-ms-date', [DateTime]::UtcNow.ToString('r')) | Out-Null
                $request.Headers.TryAddWithoutValidation('x-ms-documentdb-partitionkey', $unit.Key) | Out-Null
                $request.Headers.TryAddWithoutValidation('x-ms-documentdb-is-upsert', 'true') | Out-Null

                $response = $null

                try {
                    $response = $client.Send($request)
                    $status = [int]$response.StatusCode

                    if ($status -lt 300) {
                        [pscustomobject]@{ Container = $unit.Container; Status = 'ok'; Detail = $null; Retries = $attempt - 1 }
                        break
                    }

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
                        Container = $unit.Container
                        Status    = $status
                        Detail    = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        Retries   = $attempt - 1
                    }
                    break
                }
                catch {
                    if ($attempt -lt $maxAttempts) {
                        Start-Sleep -Milliseconds 500
                        continue
                    }

                    [pscustomobject]@{
                        Container = $unit.Container
                        Status    = 0
                        Detail    = $_.Exception.Message
                        Retries   = $attempt - 1
                    }
                    break
                }
                finally {
                    if ($response) { $response.Dispose() }
                    $request.Dispose()
                }
            }
        }
    }
    finally {
        $client.Dispose()
    }

    $throttled = @($outcomes | Where-Object { $_.Retries -gt 0 }).Count
    $failures = @($outcomes | Where-Object { $_.Status -ne 'ok' })

    if ($throttled -gt 0) {
        Write-Log "SEED $throttled item(s) were retried after throttling (429). Consider a lower -SeedConcurrency."
    }

    if ($failures.Count -gt 0) {
        $first = $failures[0]
        Write-Log "SEED FAILED $($failures.Count) of $($work.Count). First: $($first.Container) HTTP $($first.Status). $($first.Detail)"

        if ($first.Status -eq 401 -or $first.Status -eq 403) {
            throw "Authorization failed writing to $($first.Container) (HTTP $($first.Status)). A new role assignment can take a few minutes to propagate. Wait, then re-run this script."
        }

        throw "Failed writing $($failures.Count) of $($work.Count) items. The first failure was $($first.Container), HTTP $($first.Status)."
    }

    foreach ($group in @($outcomes | Where-Object { $_.Status -eq 'ok' } | Group-Object Container)) {
        Write-Log "SEED loaded $($group.Count) items into $($group.Name)."
        Write-Host "    Loaded $($group.Count) items into $($group.Name)." -ForegroundColor Green
    }
}

#endregion

#region Main

$Location = ($Location -replace '\s', '').ToLowerInvariant()
$FoundryLocation = ($FoundryLocation -replace '\s', '').ToLowerInvariant()
if ($SecondaryLocation) { $SecondaryLocation = ($SecondaryLocation -replace '\s', '').ToLowerInvariant() }

if ($EmbeddingOnly -and -not $EnableFoundry) {
    throw '-EmbeddingOnly requires -EnableFoundry.'
}
if ($AccountOnly -and $SearchFeaturesReady) {
    throw 'Choose -AccountOnly for stage one or -SearchFeaturesReady for stage two, not both.'
}
if ($LabProfile -in @('search', 'agentmemory', 'aitools') -and -not $AccountOnly -and -not $PreflightOnly) {
    if (-not $SearchFeaturesReady -or -not $AccountName) {
        throw 'First run with -AccountOnly. Enable vector and full-text search in the account Features pane and wait for enrollment to complete. Then rerun with -AccountName and -SearchFeaturesReady. No databases or containers have been created by this run.'
    }
}

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

$accountCount = if ($Profiles[$LabProfile].Account.AccountCount) { $Profiles[$LabProfile].Account.AccountCount } else { 1 }

if ($AccountName -and ($accountCount -gt 1 -or $AccountName -notmatch '^[a-z0-9][a-z0-9-]{1,42}[a-z0-9]$')) {
    throw 'Use a valid 3-44 character Cosmos DB account name. Profiles that create multiple accounts require -NamePrefix instead of -AccountName.'
}
Initialize-ResourceProviders -CheckOnly:$PreflightOnly

$resourceGroupExists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'json') | ConvertFrom-Json
$existingAccounts = @()
if ($resourceGroupExists) {
    $existingAccounts = @(Invoke-Az @('cosmosdb', 'list', '--resource-group', $ResourceGroup, '--output', 'json') | ConvertFrom-Json)
}

if ($AccountName) {
    $accountNames = @($AccountName)
}
else {
    # Re-use accounts this script created earlier. Without this, a re-run after a
    # mid-script failure generates fresh names and leaves extra billable accounts behind.
    $existing = @($existingAccounts | Where-Object { $_.name.StartsWith($NamePrefix) } | ForEach-Object { $_.name } | Sort-Object)

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

Assert-LabAvailability -AccountNames $accountNames -ExistingAccounts $existingAccounts -ResourceGroupExists $resourceGroupExists

if ($PreflightOnly) {
    Write-Step 'Preflight-only run complete. No Azure resources were created or changed.'
    return
}

Initialize-Subscription

$provisioned = @()
$foundryResources = @()
$databases = $Profiles[$LabProfile].Databases

foreach ($name in $accountNames) {
    # The provisioning and seeding functions read $AccountName from this scope.
    $AccountName = $name

    $existingAccount = Get-LabAccount

    $principalId = ''
    if (-not $AccountOnly) {
        if ($Profiles[$LabProfile].Account.GrantDataPlaneAccess -eq $false) {
            Write-Step 'This profile grants no data-plane role to the signed-in user. The exercise assigns scoped roles itself.'
        }
        else {
            # The account has key authentication disabled, so without this role nothing
            # can read or write, including the seed step below.
            $principalId = (Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv')).Trim()
        }
    }

    $endpoint = Invoke-LabDeployment -DeployAccount (-not $existingAccount) -PrincipalId $principalId

    if ($EnableFoundry) {
        $foundryPrincipalId = if ($principalId) { $principalId } else {
            (Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv')).Trim()
        }
        $foundryResources += Invoke-FoundryDeployment -PrincipalId $foundryPrincipalId
    }

    if (-not $AccountOnly -and -not $SkipSeed) {
        Add-SeedData -Endpoint $endpoint -Databases $databases
    }

    $provisioned += [pscustomobject]@{ Name = $name; Endpoint = $endpoint }
}

$endTime = Get-Date
$totalElapsed = Format-Duration ($endTime - $script:StartTime)

Write-Log "Finished       : $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "Total run time : $totalElapsed"

Write-Host ''
if ($AccountOnly) {
    Write-Host 'Cosmos DB account stage complete. Cosmos databases, containers, roles, and seed data are not provisioned yet.' -ForegroundColor Yellow
    Write-Host 'Complete feature enrollment in the portal, then rerun with this AccountName and -SearchFeaturesReady.' -ForegroundColor Yellow
}
else {
    Write-Host "Setup complete. Record $(if ($provisioned.Count -gt 1) { 'these values' } else { 'these two values' })." -ForegroundColor Green
}
Write-Host ''
foreach ($account in $provisioned) {
    Write-Host "  Account name     : $($account.Name)" -ForegroundColor Yellow
    Write-Host "  Account endpoint : $($account.Endpoint)" -ForegroundColor Yellow
    Write-Host ''
}
foreach ($foundry in $foundryResources) {
    Write-Host "  Foundry account  : $($foundry.FoundryAccountName)" -ForegroundColor Yellow
    Write-Host "  Foundry project  : $($foundry.FoundryProjectName)" -ForegroundColor Yellow
    Write-Host "  Foundry region   : $($foundry.FoundryLocation)"
    Write-Host "  OpenAI endpoint  : $($foundry.OpenAiEndpoint)" -ForegroundColor Yellow
    Write-Host "  Project endpoint : $($foundry.ProjectEndpoint)"
    Write-Host "  Embedding model  : $($foundry.EmbeddingDeployment) ($($foundry.EmbeddingDimensions) dimensions)" -ForegroundColor Yellow
    if ($foundry.ChatDeployment) { Write-Host "  Chat model       : $($foundry.ChatDeployment)" -ForegroundColor Yellow }
    Write-Host "  Foundry settings : $(Join-Path $script:ScriptRoot "logs/foundry-$($foundry.CosmosAccountName).json")"
    Write-Host '  A new Foundry role assignment can take several minutes to propagate.'
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

