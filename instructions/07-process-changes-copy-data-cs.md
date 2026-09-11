---
lab:
  title: Process changes and copy data in C#
  module: Module 7 - Process the Azure Cosmos DB for NoSQL Change Feed
  description: Run a change feed consumer against a lease container, react to changes with an Azure Functions trigger, and copy a container onto a new partition key with a copy job.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you build the pipeline described throughout this module. You load the CosmicWorks catalog and run a consumer. The consumer keeps the denormalized category name current. You then run the same logic in an Azure Function. Finally, you copy the data to a container that uses a different partition key.

The category name that products carry is a copy. Renaming a category in one container leaves that copy stale everywhere else until something reconciles it, and the change feed is what makes the reconciliation possible without polling.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

This exercise also requires:

- [Azure Functions Core Tools](/azure/azure-functions/functions-run-local) version 4.
- [Azurite](/azure/storage/common/storage-use-azurite), for the function's local storage.

## Set up your Azure Cosmos DB resources

The core exercises reuse an account prepared with the `core` profile, not the two-item account from the first portal exercise. Before skipping setup, open **Allfiles/Labs/Shared** in PowerShell, sign in with `az login`, and set `$resourceGroup`, `$location`, and `$accountName` to your recorded values. Run `./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile core` and continue only when it succeeds. In Data Explorer, confirm 295 items in `cosmicworks/product` and 237 in `cosmicworks/productMeta` with `SELECT VALUE COUNT(1) FROM c`.

If you have no verified core account, follow the setup steps below. To add missing resources to an existing lab account, pass its explicit `-AccountName` to setup rather than using a different module's name prefix. Reseeding restores canonical items but doesn't remove extra items or reset container policies. Resolve mismatches before continuing; don't reset a shared account automatically.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI. A browser window opens so you can sign in to Azure.

    ```azurecli
    az login
    ```

1. Set variables for the resource group (If a resource group was provided by your lab environment, use that name) and region you want to use. Change either value if you prefer a different resource group name or region.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab07 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab07a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds every container this learning path uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 category and tag records |
| `leases` container | Partitioned on `/id`, 400 RU/s. The change feed processor stores its checkpoints here |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

> &#10071; Container copy jobs in Task 4 run in the account's write region and are available in a subset of Azure regions. The setup script warns you if the region you chose doesn't support them. Check the [supported regions](/azure/cosmos-db/container-copy) if you need to pick a different one.

## Task 1: Set up the project and confirm the catalog

The setup script created the `product`, `productMeta`, and `leases` containers, granted your identity data-plane access, and loaded the catalog. This task builds the project the rest of the exercise uses and confirms the data arrived.

Create a project and add the packages (remember to replace `<your-account-name>` and `<cosmos-endpoint>` with your actual values):

```bash
dotnet new console -o change-feed-lab
cd change-feed-lab
dotnet add package Microsoft.Azure.Cosmos
dotnet add package Newtonsoft.Json
dotnet add package Azure.Identity
```

Replace the contents of `Program.cs` with a count of what each container holds:

```csharp
using Azure.Identity;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";

CosmosClient client = new(endpoint, new DefaultAzureCredential());
Database database = client.GetDatabase("cosmicworks");

foreach (string name in new[] { "productMeta", "product" })
{
    Container container = database.GetContainer(name);

    FeedResponse<int> response = await container
        .GetItemQueryIterator<int>("SELECT VALUE COUNT(1) FROM c")
        .ReadNextAsync();

    Console.WriteLine($"{name}: {response.First()} items");
}
```

Run it:

```bash
dotnet run
```

```output
productMeta: 237 items
product: 295 items
```

`productMeta` holds two kinds of document discriminated by a `type` property: category documents and tag documents. That detail matters in the next task.

## Task 2: Sync a denormalized property from the change feed

Build a consumer that watches `productMeta` and rewrites `categoryName` on every product in a renamed category.

Create `Sync.cs` in the `change-feed-lab` directory:

```csharp
using Azure.Identity;
using Microsoft.Azure.Cosmos;

public record MetaItem(string id, string name, string type);
public record ProductRef(string id, string categoryId);

public static class Sync
{
    private static Container productContainer = null!;

    public static async Task RunAsync(string endpoint)
    {
        CosmosClient client = new(endpoint, new DefaultAzureCredential());
        Database database = client.GetDatabase("cosmicworks");

        productContainer = database.GetContainer("product");
        Container monitoredContainer = database.GetContainer("productMeta");
        Container leaseContainer = database.GetContainer("leases");

        ChangeFeedProcessor processor = monitoredContainer
            .GetChangeFeedProcessorBuilder<MetaItem>(
                processorName: "categoryNameSync",
                onChangesDelegate: HandleChangesAsync)
            .WithInstanceName("lab-worker")
            .WithLeaseContainer(leaseContainer)
            .Build();

        await processor.StartAsync();
        Console.WriteLine("Processor started. Press any key to stop.");
        Console.ReadKey();
        await processor.StopAsync();
    }

    private static async Task HandleChangesAsync(
        ChangeFeedProcessorContext context,
        IReadOnlyCollection<MetaItem> changes,
        CancellationToken cancellationToken)
    {
        foreach (MetaItem item in changes)
        {
            if (item.type != "category")
            {
                continue;
            }

            QueryDefinition query = new QueryDefinition(
                    "SELECT p.id, p.categoryId FROM product p WHERE p.categoryId = @categoryId")
                .WithParameter("@categoryId", item.id);

            int updated = 0;
            using FeedIterator<ProductRef> iterator =
                productContainer.GetItemQueryIterator<ProductRef>(query);

            while (iterator.HasMoreResults)
            {
                foreach (ProductRef product in await iterator.ReadNextAsync())
                {
                    await productContainer.PatchItemAsync<dynamic>(
                        product.id,
                        new PartitionKey(product.categoryId),
                        new[] { PatchOperation.Set("/categoryName", item.name) });
                    updated++;
                }
            }

            Console.WriteLine($"Category '{item.name}' synced to {updated} products.");
        }
    }
}
```

`Sync.cs` only defines a class, and `dotnet run` starts the project's entry point rather than a file you name, so nothing you do runs `Sync.cs` on its own. The call belongs in `Program.cs` instead. Replace that file's entire contents with one line. The counting code from Task 1 has done its job, and `Sync.cs` carries its own `using` directives:

```csharp
await Sync.RunAsync("<cosmos-endpoint>");
```

Run the consumer:

```bash
dotnet run
```

```output
Processor started. Press any key to stop.
```

Leave this terminal open and the consumer running. `Sync.RunAsync` waits at `Console.ReadKey`, so the processor keeps watching the feed until you stop it, and the next step depends on it still running.

With the consumer running, rename a category from a second terminal. Category `3E4CEACD-D007-46EB-82D7-31F6141752B2` is *Components, Road Frames*, and its partition key value is `category`.

In the second terminal, open the parent folder of `change-feed-lab`. Create a sibling console project and install its dependencies:

```powershell
dotnet new console -o rename-category
cd rename-category
dotnet add package Microsoft.Azure.Cosmos
dotnet add package Newtonsoft.Json
dotnet add package Azure.Identity
```

Replace `Program.cs` in `rename-category` with:

```csharp
using Azure.Identity;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
const string categoryId = "3E4CEACD-D007-46EB-82D7-31F6141752B2";

CosmosClient client = new(endpoint, new DefaultAzureCredential());
Container container = client.GetContainer("cosmicworks", "productMeta");

string newName = $"Components, Road Frames (revised {DateTime.UtcNow:HHmmss})";

await container.PatchItemAsync<dynamic>(
    categoryId,
    new PartitionKey("category"),
    new[] { PatchOperation.Set("/name", newName) });

Console.WriteLine($"Renamed category to '{newName}'.");
```

Run the rename from this second terminal with `dotnet run`. Keep the consumer running in its original terminal.

Switch back to the consumer's terminal. It reports the new category name and the number of products it patched. Run the rename a second time to watch the consumer pick up another change.

Two behaviors are worth noticing:

- **The `type` filter is doing real work.** `productMeta` holds 200 tag documents alongside the categories. Without the filter, a tag rename would write a tag's name into `categoryName` on unrelated products.
- **The consumer starts from now.** Changes made before it first ran are invisible to it, because the start position applies only until a lease or continuation token exists.

> &#128161; Stop the consumer, run the rename program, then restart the consumer. It resumes from its stored checkpoint and processes the change made while it was stopped, because the lease documents survive the restart.

## Task 3: React to changes with an Azure Function

The consumer in Task 2 is a process you have to host or an application. In this task you run the equivalent logic on an Azure Functions instead, watching the `product` container so that the changes performed in Task 2 become this task's input.

Open a new integrated terminal in the Shared folder.

```bash
func init product-audit --worker-runtime dotnet-isolated --target-framework net10.0
cd product-audit
func new --name ProductAudit --template "CosmosDBTrigger"
dotnet add package Microsoft.Azure.Functions.Worker.Extensions.CosmosDB
```

Replace the contents of `ProductAudit.cs` with:

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

public class ProductAudit
{
    private readonly ILogger<ProductAudit> _logger;

    public ProductAudit(ILogger<ProductAudit> logger) => _logger = logger;

    [Function("ProductAudit")]
    public void Run([CosmosDBTrigger(
        databaseName: "%COSMOS_DATABASE_NAME%",
        containerName: "%COSMOS_CONTAINER_NAME%",
        Connection = "COSMOS_CONNECTION",
        LeaseContainerName = "leases")] IReadOnlyList<Product> changes,
        FunctionContext context)
    {
        if (changes is null)
        {
            return;
        }

        foreach (Product product in changes)
        {
            _logger.LogInformation(
                "Product {id} is now in category '{category}'.",
                product.id,
                product.categoryName);
        }
    }
}

public record Product(string id, string categoryId, string categoryName, string name);
```

Set `local.settings.json`:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "COSMOS_DATABASE_NAME": "cosmicworks",
    "COSMOS_CONTAINER_NAME": "product",
    "COSMOS_CONNECTION__accountEndpoint": "<cosmos-endpoint>"
  }
}
```

Azurite emulates Azure Storage on your own machine. The Functions host keeps its internal bookkeeping in a storage account, which is what `AzureWebJobsStorage` points at, and `UseDevelopmentStorage=true` sends that to Azurite. None of your data goes there: the catalog stays in Cosmos DB, and the change feed's checkpoints stay in the `leases` container.

Start Azurite in this terminal (this application can take a few moments to initialize):

```bash
azurite --silent
```

Start the function in a new terminal on this folder:

```bash
func start
```

> &#128221; Select **Allow** if the function requests network access.


The connection setting names an endpoint but no credential, so `DefaultAzureCredential` falls back to your `az login` session. Note what's absent from the trigger configuration: `CreateLeaseContainerIfNotExists` stays at its default, because creating a container is a control-plane operation that a data-plane role assignment doesn't permit. The `leases` container from Task 1 is already there.

Now watch the whole pipeline run:

1. Go to the terminal you used for the rename program and run it again.

1. Watch the Task 2 consumer. It reports the category it synced and how many products it patched.

1. Watch the `func start` terminal. Each patched product arrives as a separate execution, and the message is the one your own function logs:

    ```output
    Product 0AE1D2B4-... is now in category 'Components, Road Frames (revised 051233)'.
    ```

Two consumers are now reading two different feeds from the same account, and one feeds the other. The Task 2 consumer watches `productMeta` and writes to `product`. The function watches `product`, so the consumer's writes are what trigger it.

> &#128221; Both consumers share the `leases` container without colliding, because they monitor different containers and use different processor identities. Two consumers on the *same* monitored container would compete for the same leases, and one of them would sit idle. That case needs a distinct lease container prefix.

## Task 4: Copy a container onto a new partition key

Moving a container to a different partition key means copying its data into a container created with the new key. This task runs that copy yourself, with the CLI.

> &#128221; Container copy jobs are in preview. The jobs run on a best-effort basis with no service-level agreement.

Stop everything still running from the previous tasks, then close those terminals. An offline copy job requires writes on the source to be stopped, and the Task 2 consumer is the process writing to `product`. Updates made after the job starts might not be captured.

The rest of this task runs in the Azure CLI. In the **Explorer** pane, open the context menu for the **Allfiles/Labs/Shared** folder and select **Open in Integrated Terminal**, then sign in:

```azurecli
az login
```

Set the variables again, replacing `ResourceGroup1` if your lab environment provides a different resource group name. The ones you set during setup belonged to a terminal you just closed, and every command below uses them:

```powershell
$resourceGroup = "ResourceGroup1"
$accountName = "<your-account-name>"
```

Create the destination container with the new key:

```azurecli
az cosmosdb sql container create `
    --account-name $accountName `
    --resource-group $resourceGroup `
    --database-name cosmicworks `
    --name productArchive `
    --partition-key-path "/id" `
    --throughput 800
```

The copy commands currently ship in a preview extension. Install it:

```azurecli
az extension add --name cosmosdb-preview
```

Create the copy job:

```azurecli
az cosmosdb copy create `
    --resource-group $resourceGroup `
    --job-name product-to-archive `
    --src-account $accountName `
    --dest-account $accountName `
    --src-nosql database=cosmicworks container=product `
    --dest-nosql database=cosmicworks container=productArchive
```

The command returns as soon as the job is registered, before any data moves, so the response reports `"status": "Pending"` with `"totalCount": 0` and `"processedCount": 0`.

Monitor it, give it a few moments, and you need to run the `az cosmosdb copy show` command repeatedly until the `status` reads `Completed`:

```azurecli
az cosmosdb copy show `
    --resource-group $resourceGroup `
    --account-name $accountName `
    --job-name product-to-archive
```

```output
"duration": "00:00:05.4670000",
"processedCount": 295,
"status": "Completed",
"totalCount": 295,
```

Read `status` to decide whether the job is finished. Don't rely on the two counts matching: they both sit at zero while the job is still pending, so they match before any work happens. Run the command again until `status` reads `Completed`. A job that fails reports `Faulted` and puts the reason in the `error` property.

The job reads the source container's change feed, which is the same mechanism the previous two tasks used. `totalCount` is what the job found to copy and `processedCount` is what it wrote, so a completed job shows the same number twice.

Confirm the copy in the Azure portal: open **Data Explorer**, select the `productArchive` container, and run `SELECT VALUE COUNT(1) FROM c`. It returns 295, the same count `product` holds.

The items themselves are unchanged, and each one keeps its original `id`. What changed is the container around them: `product` partitions on `/categoryId`, while `productArchive` partitions on `/id`.

The same job shape moves a container onto a hierarchical partition key, which is one of the documented reasons to run a copy. Before running that migration on your own container, confirm that the combination of `id` and the new partition key value stays unique across the container, because uniqueness is enforced on that pair and a collision fails the job.

## Clean up resources

When you finish the course, delete the resource group only if you created it and every resource in it can be removed. If your lab provided `ResourceGroup1`, skip this command and delete only the exercise resources you no longer need:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

The `leases` and `productArchive` containers consume provisioned throughput for as long as they exist, so leaving them in place has a running cost.
