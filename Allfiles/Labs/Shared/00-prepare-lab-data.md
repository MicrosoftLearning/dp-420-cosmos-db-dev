---
lab:
  title: 'Prepare the lab data'
  module: 'Setup'
---

# Prepare the lab data

The exercises in this course share one Azure Cosmos DB account but need different databases, containers, and sample data. The setup script groups those differences into seven **lab profiles**.

Each exercise names the profile it needs in its **Before you start** section.

## The core profile

Serves the resources and throughput, SDK connection, data operations, query, change feed, and AI-assisted tools exercises.

```powershell
$resourceGroup = "dp420"
$location = "eastus"

./setup.ps1 -ResourceGroup $resourceGroup -Location $location
```

It creates a `cosmicworks` database holding five containers:

| Container | Partition key | Throughput | Contents |
| :--- | :--- | :--- | :--- |
| `product` | `/categoryId` | Autoscale, 1000 RU/s max | 295 CosmicWorks products |
| `productMeta` | `/type` | Autoscale, 1000 RU/s max | 237 category and tag documents |
| `leases` | `/id` | 400 RU/s manual | Empty. The change feed processor writes here |
| `operations` | `/categoryId` | Autoscale, 1000 RU/s max | Empty. The data operations exercise works here |
| `bulkload` | `/categoryId` | Autoscale, 1000 RU/s max | Empty. The bulk task writes here |

`leases` uses `/id` because the change feed processor requires it. That's a product requirement, not a preference.

## The modeling profile

Serves the data modeling and partitioning exercise, which compares the cost of the same query against four progressively different models of the same data.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -LabProfile modeling
```

It creates four databases:

| Database | Model |
| :--- | :--- |
| `database-v1` | The relational schema lifted directly into Azure Cosmos DB |
| `database-v2` | Customer addresses and credentials embedded; product data still referenced |
| `database-v3` | Category and tag names denormalized onto the product |
| `database-v4` | Entity types merged: customers with their sales orders, categories with tags |

The four databases hold 22 containers between them, each partitioned on the key its modeling stage calls for, so this profile takes longer to run than `core`.

## The security profile

Serves the security exercise, which switches public network access off and back on. Give it a resource group of its own so its cleanup step can't reach your shared course account.

```powershell
./setup.ps1 -ResourceGroup "dp420-security" -Location $location -NamePrefix dp420lab09 -LabProfile security
```

It creates a serverless account with key-based authentication disabled and public network access enabled, holding a `cosmicworks` database with one empty `product` container partitioned on `/categoryId`.

Nothing is seeded and no data-plane role is granted to you. The exercise loads the catalog through a hosted managed identity and assigns that identity container-scoped roles, which is the behavior it measures.

## The backup profile

Serves the backup and restore exercise. Continuous backup can only be chosen when an account is created, so this profile creates its own account, and the exercise deletes it at the end. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-backup" -Location $location -NamePrefix dp420lab10 -LabProfile backup
```

It creates an account with a backup policy of `Continuous` at the `Continuous7Days` tier, holding a `cosmicworks` database with one empty `product` container partitioned on `/categoryId` at 400 RU/s.

The container is left empty on purpose. The exercise loads the catalog itself, so the restore point it captures sits after a write it performed and can be verified against a known item count.

## The multiregion profile

Serves the multi-region availability and failover exercise. That exercise changes the account's write region and then takes a region offline, and a region that goes offline stays offline until Microsoft restores it, so this profile creates its own account. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-multiregion" -Location $location -NamePrefix dp420lab11 -LabProfile multiregion
```

It creates an account in **two** regions, holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

Both regions are created at once because adding a region to an existing account replicates the data first, which takes far longer than creating the account with both regions in place.

The script picks the second region for you from the region you pass to `-Location`. To choose it yourself, add `-SecondaryLocation`:

```powershell
./setup.ps1 -ResourceGroup "dp420-multiregion" -Location "eastus" -SecondaryLocation "westus" -NamePrefix dp420lab11 -LabProfile multiregion
```

Throughput and storage are billed per region, so a two-region account costs about twice what the same account costs in one region. Delete the resource group as soon as you finish the exercise.

## The indexing profile

Serves the indexing strategy exercise. Global secondary indexes require continuous backup on the account, and continuous backup can only be chosen when an account is created, so this profile creates its own account. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-indexing" -Location $location -NamePrefix dp420lab12 -LabProfile indexing
```

It creates an account with a backup policy of `Continuous` at the `Continuous7Days` tier, holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

The exercise enables the global secondary index feature on the account itself, because doing so is part of what the exercise teaches.

## The monitoring profile

Serves the monitoring and troubleshooting exercise. That exercise attaches a diagnostic setting and a metric alert rule to the account and then deletes the whole resource group, so this profile creates its own account. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-monitoring" -Location $location -NamePrefix dp420lab14 -LabProfile monitoring
```

It creates an account holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at **400 RU/s manual throughput**, seeded with the 295 CosmicWorks products.

Manual throughput is deliberate. The exercise has to reach rate limiting inside its time budget, and an autoscale maximum would let the container absorb the load instead of returning 429 responses.

## The fleet profile

Serves the fleets exercise. A fleet groups accounts, so this is the only profile that creates more than one, and the exercise deletes the whole resource group when it finishes. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-fleet" -Location $location -NamePrefix dp420lab15 -LabProfile fleet
```

It creates **two** accounts, each holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

Both accounts are created in the same single region with the same single-region write configuration on purpose. Accounts can share a fleetspace throughput pool only when their regions and their service tier match, so two accounts that differ in either respect can't be enrolled in the same fleetspace. Because this profile creates more than one account, it doesn't accept `-AccountName`.

This profile takes roughly twice as long to run as the others, because the accounts are created one after the other.

## Verify the result

1. In a browser, open the [Azure portal](https://portal.azure.com) and go to your Azure Cosmos DB account.
1. In the resource menu, select **Data Explorer**.
1. Confirm the databases and containers for your profile appear in the tree.
1. Expand a seeded container and select **Items** to confirm the sample data loaded.

## Provision without loading data

To create the databases and containers but skip the sample data, add `-SkipSeed`:

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -SkipSeed
```

The SDK connection and data operations exercises write their own items, so they work fine against an unseeded account.

## Load the data by hand

If the script can't run in your environment, you can load the `core` data through the portal instead. The source files are JSON arrays in the [CosmicWorks repository](https://github.com/AzureCosmosDB/CosmicWorks/tree/main/data/database-v4).

1. Download `product` and `productMeta` from `data/database-v4`, saving each with a `.json` extension.
1. In **Data Explorer**, expand the `cosmicworks` database and the target container, and then select **Items**.
1. Select **Upload Item**, browse to the file, and select **Upload**.
1. Repeat for the second container.

This approach doesn't scale to the `modeling` profile, which has far more containers.

## Troubleshooting

| Message | Cause | Fix |
| :--- | :--- | :--- |
| `Authorization failed writing to <container> (HTTP 403)` | The role assignment hasn't propagated | Wait a few minutes and re-run the script |
| `You are not signed in to the Azure CLI` | No active session | Run `az login` |
| Account name rejected | The name you passed with `-AccountName` isn't valid | Omit `-AccountName` and let the script generate one |
| `MissingSubscriptionRegistration` | Resource provider not registered | See [Register Azure resource providers](00-register-resource-providers.md) |
