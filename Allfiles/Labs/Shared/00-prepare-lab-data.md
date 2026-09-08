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
./setup.ps1 -ResourceGroup "dp420-modeling" -Location $location -NamePrefix dp420lab06 -LabProfile modeling
```

Use a dedicated resource group, not the core account's group, because the exercise removes its modeling resources when you finish. It creates four databases:

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

## The mirroring profile

Serves the operational analytics exercise. Microsoft Fabric mirroring requires continuous backup on the source account, continuous backup can only be chosen when an account is created, and it can never be turned off again, so this profile creates its own account. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-mirroring" -Location $location -NamePrefix dp420lab20 -LabProfile mirroring
```

It creates an account with a `Continuous` backup policy at the `Continuous7Days` tier, holding a `cosmicworks` database with two containers, both at an autoscale maximum of 1000 RU/s:

- `product`, partitioned on `/categoryId`, seeded with the 295 CosmicWorks products.
- `customer`, partitioned on `/customerId`, seeded with the 282 CosmicWorks customer documents.

Both containers are seeded, unlike most disposable profiles, because the exercise reads the mirrored copy of this data rather than writing it. The `customer` container is included for a specific reason: it holds two document types in one container, 10 customers and 272 sales orders, discriminated by a `type` property. Nine properties appear only on the customer documents and three only on the sales order documents, so the mirrored warehouse table is the union of both shapes and every row is null in the other type's columns. That is what makes mirroring's schema handling observable rather than theoretical.

The 7-day continuous tier is chosen because it is the free tier, and mirroring works the same on either tier.

## The fleet profile

Serves the fleets exercise. A fleet groups accounts, so this is the only profile that creates more than one, and the exercise deletes the whole resource group when it finishes. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-fleet" -Location $location -NamePrefix dp420lab15 -LabProfile fleet
```

It creates **two** accounts, each holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

Both accounts are created in the same single region with the same single-region write configuration on purpose. Accounts can share a fleetspace throughput pool only when their regions and their service tier match, so two accounts that differ in either respect can't be enrolled in the same fleetspace. Because this profile creates more than one account, it doesn't accept `-AccountName`.

This profile takes roughly twice as long to run as the others, because the accounts are created one after the other.

## The search profile

Serves the full-text and vector search exercise. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-search" -Location $location -NamePrefix dp420lab16 -LabProfile search -AccountOnly
```

Record the account name. In its portal **Features** pane, enable **Full Text & Hybrid Search for NoSQL API** and confirm **Vector Search for NoSQL API** is enabled. Allow up to 15 minutes for enrollment. Only after both are enabled, complete setup against that account:

```powershell
$accountName = "<account-name-from-stage-one>"
./setup.ps1 -ResourceGroup "dp420-search" -Location $location -AccountName $accountName -LabProfile search -SearchFeaturesReady
```

The confirmation switch records your portal check and doesn't enable the features. The completed setup creates an account with the `EnableNoSQLVectorSearch` capability, a `cosmicworks` database, and a `productSearch` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s. The container carries a full-text policy and full-text index on `/searchText`, a vector policy on `/embedding` (`float32`, 1536 dimensions, cosine), a `diskANN` vector index on the same path, and `/embedding/*` in the excluded paths.

The account is disposable for two reasons. Vector search is an account capability that can't be turned off once it's enabled, and a container's vector policy is fixed at creation, so neither can be added to the shared course account without changing it permanently.

The container is left empty on purpose. The exercise builds the `searchText` property and calls an embedding model itself, so seeding here would store items with no vector at the path the vector index covers.

The `EnableNoSQLVectorSearch` capability can take up to 15 minutes to take effect after the account is created. Full-text search is enabled separately, from the **Features** pane of the account in the Azure portal.

## The agentmemory profile

Serves the agent memory exercise. Give it a resource group of its own.

```powershell
./setup.ps1 -ResourceGroup "dp420-agentmemory" -Location $location -NamePrefix dp420lab19 -LabProfile agentmemory -AccountOnly
```

Complete the same portal enrollment checks as for `search`, then resume against the recorded account:

```powershell
$accountName = "<account-name-from-stage-one>"
./setup.ps1 -ResourceGroup "dp420-agentmemory" -Location $location -AccountName $accountName -LabProfile agentmemory -SearchFeaturesReady
```

The completed setup creates an account with the `EnableNoSQLVectorSearch` capability, an `agentmemory` database, and two containers, both at an autoscale maximum of 1000 RU/s:

- `conversation`, partitioned on `/threadId`, with a default time to live of 2,592,000 seconds. Conversation turns clear themselves 30 days after their last write.
- `memory`, partitioned on `/userId`, with a default time to live of `-1`. That value enables time to live on the container while expiring nothing by default, so a memory expires only when the item carries its own `ttl`. The container also carries a full-text policy and index on `/content`, a vector policy on `/embedding` (`float32`, 1536 dimensions, cosine), a `quantizedFlat` vector index on the same path, and `/embedding/*` in the excluded paths.

The two containers differ in partition key on purpose. Conversation state is read one thread at a time, and long-term memory is read across every thread one person ever opened.

The account is disposable for the same reason as the `search` profile: vector search is an account capability that can't be turned off once it's enabled, and a container's vector policy is fixed at creation.

Both containers are left empty. The exercise writes the turns and distills the memories itself.

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
