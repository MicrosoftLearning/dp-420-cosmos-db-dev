---
lab:
  title: 'Prepare the lab data'
  module: 'Setup'
---

# Prepare the lab data

The exercises in this course share one Azure Cosmos DB account but need different databases, containers, and sample data. The setup script groups those differences into two **lab profiles**.

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
