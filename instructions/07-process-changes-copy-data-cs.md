---
lab:
  title: Process changes and copy data in C#
  module: Module 7 - Process the Azure Cosmos DB for NoSQL Change Feed
  description: Synchronize product category names with the change feed, log updates with an Azure Functions trigger, and copy a container to a new partition key.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Process changes and copy data in C#

In this exercise, you use the change feed to keep product category names in sync, log product updates with an Azure Function, and copy products to a container with a different partition key.

Products store a copy of the category name from `productMeta`. A category rename updates the metadata document; the consumer updates the corresponding products.

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

Use the account endpoint recorded during setup wherever the code contains `<cosmos-endpoint>`.

Create a project and install the required packages:

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

// Use a developer credential, such as az login, instead of an account key.
CosmosClient client = new(endpoint, new DefaultAzureCredential());
Database database = client.GetDatabase("cosmicworks");

foreach (string name in new[] { "productMeta", "product" })
{
    Container container = database.GetContainer(name);

    // SELECT VALUE returns a scalar count, so deserialize the result as int.
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

The `type` property distinguishes category documents from tag documents in `productMeta`.

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

        // Watch metadata, then update the denormalized categoryName elsewhere.
        productContainer = database.GetContainer("product");
        Container monitoredContainer = database.GetContainer("productMeta");
        Container leaseContainer = database.GetContainer("leases");

        // Leases persist progress and coordinate workers. The processor name
        // identifies the consumer, while the instance name identifies this worker.
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
            // productMeta mixes category and tag documents; only categories drive this sync.
            if (item.type != "category")
            {
                continue;
            }

            // The category document's id matches categoryId on the related products.
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
                    // Delivery can repeat. Setting an absolute value is replay-safe;
                    // the product writes aren't one cross-container transaction.
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

Replace all the contents of `Program.cs` with the following to start the consumer:

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

Leave this terminal open with the consumer running while you perform the next steps.

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

// Change the value on each run so the consumer has a new update to observe.
string newName = $"Components, Road Frames (revised {DateTime.UtcNow:HHmmss})";

// This metadata container uses /type: the partition key is "category", not the GUID.
await container.PatchItemAsync<dynamic>(
    categoryId,
    new PartitionKey("category"),
    new[] { PatchOperation.Set("/name", newName) });

Console.WriteLine($"Renamed category to '{newName}'.");
```

Run the rename from this second terminal with `dotnet run`. Keep the consumer running in its original terminal.

Switch back to the consumer's terminal. It reports the new category name and the number of products it patched. Run the rename a second time to watch the consumer pick up another change.

Review the consumer's behavior:

- **Metadata filtering:** The feed contains category and tag documents. Only category changes require updates to the products.
- **Start position:** On its first run, the consumer starts with future changes.

> &#128161; Stop the consumer, rename the category, and restart the consumer. It resumes from its stored checkpoint and processes the change.

## Task 3: React to changes with an Azure Function

Use an Azure Functions trigger to log changes to `product`. The Task 2 consumer's product updates trigger the function.

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

    // The binding resolves %...% from host settings and uses leases for feed progress.
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

        // Log each product in the change feed batch.
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

Azurite provides local storage for the Functions host. The catalog remains in Azure Cosmos DB, and the function's change feed checkpoints are stored in `leases`.

Start Azurite in this terminal (this application can take a few moments to initialize):

```bash
azurite --silent
```

Start the function in a new terminal on this folder:

```bash
func start
```

> &#128221; Select **Allow** if the function requests network access.


The function uses your Azure CLI sign-in and the existing `leases` container.

Test the pipeline:

1. Go to the terminal you used for the rename program and run it again.

1. Watch the Task 2 consumer. It reports the category it synced and how many products it patched.

1. Watch the `func start` terminal for product update messages:

    ```output
    Product 0AE1D2B4-... is now in category 'Components, Road Frames (revised 051233)'.
    ```

## Task 4: Copy a container onto a new partition key

Create a destination container with the new partition key and copy the source data into it.

> &#128221; Container copy jobs are in preview. The jobs run on a best-effort basis with no service-level agreement.

Stop the consumer, function, and Azurite, then close their terminals. Don't write to the source container while the offline copy job runs.

The rest of this task runs in the Azure CLI. In the **Explorer** pane, open the context menu for the **Allfiles/Labs/Shared** folder and select **Open in Integrated Terminal**, then sign in:

```azurecli
az login
```

Set the variables in this new terminal. Use your lab's resource group name and the account name recorded during setup:

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

Install the preview extension for the copy commands:

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

The command creates an asynchronous copy job. Monitor its progress with the following command until `status` is `Completed`:

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

The copy job reads the source container's change feed. A completed job should report 295 for both `totalCount` and `processedCount`.

Confirm the copy in the Azure portal: open **Data Explorer**, select the `productArchive` container, and run `SELECT VALUE COUNT(1) FROM c`. It returns 295, the same count `product` holds.

The copied items retain their original `id` values. The destination container partitions on `/id` instead of `/categoryId`.

For other migrations, make sure the combination of `id` and the new partition key value remains unique within the container.

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
