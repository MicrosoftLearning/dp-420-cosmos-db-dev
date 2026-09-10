---
lab:
  title: 'Prepare the lab data'
  module: 'Setup'
---

# Prepare the lab data

The exercises use shared or disposable Azure Cosmos DB accounts with different databases, containers, and sample data. The setup script groups those differences into **lab profiles**. The optional `-EnableFoundry` switch also provisions the model resources used by the AI exercises.

Use the profile named in your exercise's **Set up your Azure Cosmos DB resources** section. The profiles here are alternatives, not a sequence to run.

Run the commands for your chosen profile in a PowerShell terminal opened in **Allfiles/Labs/Shared**. First set these values from your exercise. If your lab environment supplies a resource group, use that name:

```powershell
$resourceGroup = "<your-lab-resource-group>"
$location = "<region-from-your-exercise>"
```

Keep the same resource group when rerunning setup. Follow your exercise's cleanup instructions and preserve any supplied resource group.

## The core profile

Serves the resources and throughput, SDK connection, data operations, query, and change feed exercises.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -LabProfile core
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

## The aitools profile

Serves module 8, the AI-assisted development tools exercise. Use a disposable account. If the lab provides a resource group, use that group; otherwise, choose a new group for this exercise.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab08 -LabProfile aitools -EnableFoundry -FoundryLocation eastus
```

Wait for **Setup complete**. The script configures search and handles vector activation delays during container setup. Record the account name, then verify the resources:

```powershell
$accountName = "<account-name-from-setup>"
./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile aitools -EnableFoundry
```

The profile includes the five `core` containers in `cosmicworks`, with the same data and settings. It adds an `ai_memory` database with five containers:

| Container | Partition key paths | Default TTL |
| :--- | :--- | :--- |
| `memories` | `/user_id`, `/thread_id` | Enabled, no default expiry (`-1`) |
| `memories_turns` | `/user_id`, `/thread_id` | 2,592,000 seconds |
| `memories_summaries` | `/user_id`, `/thread_id` | Enabled, no default expiry (`-1`) |
| `counter` | `/user_id`, `/thread_id` | Off |
| `leases` | `/id` | Off |

Each new container uses dedicated autoscale with a maximum of 1,000 request units per second. The three memory data containers have a `/content` full-text policy and index plus a `/embedding` vector policy and `quantizedFlat` index (`float32`, 1,536 dimensions, cosine). The summaries container also has the composite index the toolkit's summary reads need. Time to live (TTL) expires raw turns after 30 days.

`foundry.bicep` deploys the Foundry project, embedding model, chat model, and user role separately from `cosmos.bicep`. The application uses `connect_cosmos` to open the resulting memory store; it doesn't create databases or containers through the data-plane SDK.

## The modeling profile

Serves the data modeling and partitioning exercise, which compares the cost of the same query against four progressively different models of the same data.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab06 -LabProfile modeling
```

Use a separate account, not the shared `core` account, because you remove the modeling resources when you finish. This profile creates four databases:

| Database | Model |
| :--- | :--- |
| `database-v1` | The relational schema lifted directly into Azure Cosmos DB |
| `database-v2` | Customer addresses and credentials embedded; product data still referenced |
| `database-v3` | Category and tag names denormalized onto the product |
| `database-v4` | Entity types merged: customers with their sales orders, categories with tags |

The four databases hold 22 containers between them, each partitioned on the key its modeling stage calls for, so this profile takes longer to run than `core`.

## The security profile

Serves the security exercise, which switches public network access off and back on. Use a dedicated account so those changes don't affect your shared course account.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab09 -LabProfile security
```

It creates a serverless account with key-based authentication disabled and public network access enabled, holding a `cosmicworks` database with one empty `product` container partitioned on `/categoryId`.

Nothing is seeded and no data-plane role is granted to you. The exercise loads the catalog through a hosted managed identity and assigns that identity container-scoped roles, which is the behavior it measures.

## The backup profile

Serves the backup and restore exercise. Use its dedicated account because the exercise deletes and restores data. Setup enables continuous backup on the new account; it doesn't migrate an existing account.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab10 -LabProfile backup
```

It creates an account with a backup policy of `Continuous` at the `Continuous7Days` tier, holding a `cosmicworks` database with one empty `product` container partitioned on `/categoryId` at 400 RU/s.

The container is left empty on purpose. The exercise loads the catalog itself, so the restore point it captures sits after a write it performed and can be verified against a known item count.

## The multiregion profile

Serves the multi-region availability and failover exercise. That exercise changes the account's write region and then takes a region offline, and a region that goes offline stays offline until Microsoft restores it, so this profile creates its own account. Don't use your shared course account.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab11 -LabProfile multiregion
```

It creates an account in **two** regions, holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

Both regions are created at once because adding a region to an existing account replicates the data first, which takes far longer than creating the account with both regions in place.

The script picks the second region for you from the region you pass to `-Location`. To choose it yourself, add `-SecondaryLocation`:

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location "eastus" -SecondaryLocation "westus" -NamePrefix dp420lab11 -LabProfile multiregion
```

Throughput and storage are billed per region, so a two-region account costs about twice what the same account costs in one region. Follow the exercise's cleanup steps when you finish. Keep a supplied resource group or one that contains other resources you need.

## The indexing profile

Serves the indexing strategy exercise. This profile creates a dedicated account with continuous backup for the global secondary index tasks. Setup doesn't migrate the backup mode on your shared account.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab12 -LabProfile indexing
```

It creates an account with a backup policy of `Continuous` at the `Continuous7Days` tier, holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

The exercise enables the global secondary index feature on the account itself, because doing so is part of what the exercise teaches.

## The monitoring profile

Serves the monitoring and troubleshooting exercise. Use a dedicated account for its diagnostic setting and metric alert rule. Remove the exercise resources when you finish, keeping any supplied resource group.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab14 -LabProfile monitoring
```

It creates an account holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at **400 RU/s manual throughput**, seeded with the 295 CosmicWorks products.

Manual throughput is deliberate. The exercise has to reach rate limiting inside its time budget, and an autoscale maximum would let the container absorb the load instead of returning 429 responses.

## The mirroring profile

Serves the operational analytics exercise. Microsoft Fabric mirroring requires continuous backup on the source account. Eligible existing accounts can [migrate to continuous backup](https://learn.microsoft.com/azure/cosmos-db/migrate-continuous-backup), but continuous backup can't be disabled afterward. This profile creates a dedicated lab account rather than migrating an existing account. Use the resource group supplied by the lab, or a new group containing only this exercise's resources.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab20 -LabProfile mirroring
```

It creates a keyless NoSQL account with a single write region, public access for all networks, and a `Continuous` backup policy at the `Continuous7Days` tier. The `cosmicworks` database holds two containers, both at an autoscale maximum of 1,000 RU/s:

- `product`, partitioned on `/categoryId`, seeded with the 295 CosmicWorks products.
- `customer`, partitioned on `/customerId`, seeded with the 282 CosmicWorks customer documents.

Both containers are seeded, unlike most disposable profiles, because the exercise reads the mirrored copy of this data rather than writing it. The `customer` container is included for a specific reason: it holds two document types in one container, 10 customers and 272 sales orders, discriminated by a `type` property. Nine properties appear only on the customer documents and three only on the sales order documents, so the mirrored warehouse table is the union of both shapes and every row is null in the other type's columns. That is what makes mirroring's schema handling observable rather than theoretical.

The 7-day tier meets the mirroring prerequisite without an extra backup-storage charge. Cosmos DB throughput, data storage, and Fabric query compute still have their own charges.

Run `./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile mirroring` after setup. Reused accounts with restricted public access or multi-region writes are rejected without changing those settings. Private-network mirroring is a supported alternative, but its workspace-specific Network ACL Bypass setup is outside this lab.

Create the custom data-plane role that grants `readMetadata` and `readAnalytics` in Task 1 of the exercise. After assigning the role, add `-CheckMirroringPermissions` to verification. This verification checks direct, account-scoped grants for your signed-in identity, not Fabric connection success or role propagation.

Provide an active Fabric capacity and assign the exercise workspace to it. Create the connection, mirrored database, lakehouse shortcuts, and notebook in the Fabric portal. No Foundry deployment, local application runtime, or Cosmos DB Spark connector is needed. Querying mirrored Delta tables uses Spark in Fabric. Preserve supplied resource groups and any reused Fabric workspace or capacity during cleanup.

## The fleet profile

Serves the fleets exercise. This profile creates two dedicated accounts. Follow the exercise's cleanup steps when you finish, keeping any supplied resource group or one that contains other resources you need.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab15 -LabProfile fleet
```

It creates **two** accounts, each holding a `cosmicworks` database with one `product` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s, seeded with the 295 CosmicWorks products.

Both accounts are created in the same single region with the same single-region write configuration on purpose. Accounts can share a fleetspace throughput pool only when their regions and their service tier match, so two accounts that differ in either respect can't be enrolled in the same fleetspace. Because this profile creates more than one account, it doesn't accept `-AccountName`.

This profile takes roughly twice as long to run as the others, because the accounts are created one after the other.

## The search profile

Serves modules 16, 17, and 18. Use each exercise's resource group, or the group supplied by your lab environment. Add `-EnableFoundry -EmbeddingOnly` for modules 16 and 17, or `-EnableFoundry` for module 18, which also needs chat.

This example is for module 16. For the other exercises, use their model switches and name prefixes.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab16 -LabProfile search -EnableFoundry -EmbeddingOnly
```

After **Setup complete** appears, record the account name and verify the resources:

```powershell
$accountName = "<account-name-from-setup>"
./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile search -EnableFoundry -EmbeddingOnly
```

The completed setup creates an account with the `EnableNoSQLVectorSearch` capability, a `cosmicworks` database, and a `productSearch` container partitioned on `/categoryId` at an autoscale maximum of 1000 RU/s. The container carries a full-text policy and full-text index on `/searchText`, a vector policy on `/embedding` (`float32`, 1536 dimensions, cosine), a `diskANN` vector index on the same path, and `/embedding/*` in the excluded paths.

The account is disposable for two reasons. Vector search is an account capability that can't be turned off once it's enabled, and a container's vector policy is fixed at creation, so neither can be added to the shared course account without changing it permanently.

The container is left empty on purpose. The exercise builds the `searchText` property and calls an embedding model itself, so seeding here would store items with no vector at the path the vector index covers.

The `EnableNoSQLVectorSearch` capability can take up to 15 minutes to take effect. Setup retries container creation when Azure reports that activation is pending. The container policies configure English full-text search without a separate portal enrollment step.

## The agentmemory profile

Serves the agent memory exercise. Use its dedicated account and the resource group you set for this exercise.

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab19 -LabProfile agentmemory -EnableFoundry
```

After **Setup complete** appears, record the account name and verify the resources:

```powershell
$accountName = "<account-name-from-setup>"
./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile agentmemory -EnableFoundry
```

The completed setup creates an account with the `EnableNoSQLVectorSearch` and `DeleteAllItemsByPartitionKey` capabilities, an `agentmemory` database, and two containers, both at an autoscale maximum of 1,000 RU/s. It also creates the Foundry embedding and chat deployments:

- `conversation`, partitioned on `/threadId`, with a default time to live of 2,592,000 seconds. Conversation turns clear themselves 30 days after their last write.
- `memory`, partitioned on `/userId`, with a default time to live of `-1`. That value enables time to live on the container while expiring nothing by default, so a memory expires only when the item carries its own `ttl`. The container also carries a full-text policy and index on `/content`, a vector policy on `/embedding` (`float32`, 1536 dimensions, cosine), a `quantizedFlat` vector index on the same path, and `/embedding/*` in the excluded paths.

The two containers differ in partition key on purpose. Conversation state is read one thread at a time, and long-term memory is read across every thread one person ever opened.

The account is disposable for the same reason as the `search` profile: vector search is an account capability that can't be turned off once it's enabled, and a container's vector policy is fixed at creation.

Both containers are left empty. The exercise writes the turns and distills the memories itself.

## Verify the result

Run `verify.ps1` with the account name, profile, and options specified by your exercise. Then check the data in the portal:

1. In a browser, open the [Azure portal](https://portal.azure.com) and go to your Azure Cosmos DB account.
1. In the resource menu, select **Data Explorer**.
1. Confirm the databases and containers for your profile appear in the tree.
1. Expand a seeded container and select **Items** to confirm the sample data loaded.

## Provision without loading data

Add `-SkipSeed` to your exercise's setup command only if the exercise explicitly tells you to skip loading sample data. Writing your own items during an exercise doesn't mean its starting data is optional. The shared `core` exercises need the catalog described here.

## Load the data by hand

If only the data-loading step fails, you can load the `core` data through the portal instead. The account, containers, and data access permissions must already exist. The source files are JSON arrays in the [CosmicWorks repository](https://github.com/AzureCosmosDB/CosmicWorks/tree/main/data/database-v4).

1. Download `product` and `productMeta` from `data/database-v4`, saving each with a `.json` extension.
1. In **Data Explorer**, expand the `cosmicworks` database and the target container, and then select **Items**.
1. Select **Upload Item**, browse to the file, and select **Upload**.
1. Repeat for the second container.

This approach doesn't scale to the `modeling` profile, which has far more containers.

## Troubleshooting

| Message | Cause | Fix |
| :--- | :--- | :--- |
| `Authorization failed writing to <container> (HTTP 403)` | The role assignment is still propagating | Wait a few minutes and rerun setup with the recorded account name |
| `You are not signed in to the Azure CLI` | No active session | Run `az login` |
| Account name rejected | The name you passed with `-AccountName` isn't valid | Check the account name and resource group you recorded. Keep the same account when retrying setup |
| `MissingSubscriptionRegistration` | Resource provider not registered | See [Register Azure resource providers](00-register-resource-providers.md) |
