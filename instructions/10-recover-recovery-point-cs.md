---
lab:
  title: Recover from a recovery point in C#
  module: Module 10 - Configure Backup and Restore in Azure Cosmos DB
  description: Enable continuous backup on an Azure Cosmos DB for NoSQL account, delete a product and its container, and restore both to a recorded point in time.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you protect an Azure Cosmos DB for NoSQL account with continuous backup, destroy data the way an accidental operation would, and recover it to a point in time you choose. You work with the real CosmicWorks product catalog, so the verification steps compare against actual data rather than placeholder values.

You load 295 products into an account provisioned at the `Continuous7Days` tier, capture a verified restore point, delete an item and then the container that held it, and restore the container into the same account. You finish by testing the boundary that same-account restore doesn't cross, and by removing everything you created.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

You also need permission to discover restorable accounts and restore their resources. For the CLI workflow in this exercise, ask your administrator for the **CosmosRestoreOperator** role at subscription scope, or equivalent permissions. Resource-group permissions and the data-plane role created by the setup script don't grant these actions. See [restore permissions](/azure/cosmos-db/continuous-backup-restore-permissions).

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

The in-account restore commands need [Azure CLI](/cli/azure/install-azure-cli) version 2.65.0 or later. Earlier versions don't accept the `--disable-ttl` option this exercise uses.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path. Enabling continuous backup on an existing account is a one-way migration, and this exercise deletes and restores the container it works in.

> [!WARNING]
> Use only the account this script creates for this exercise. Later steps delete a container and then restore it. Never point this exercise at a shared training or production account.

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

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab10 -LabProfile backup
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab10a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Confirm the applied backup policy.

    ```azurecli
    az cosmosdb show --name $accountName --resource-group $resourceGroup --query "backupPolicy"
    ```

    The output reports a `type` of `Continuous`, a `tier` of `Continuous7Days`, and a `migrationState` of `null`. Naming the tier is deliberate: an account created without `--continuous-tier` gets the charged 30-day tier.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled and continuous backup at the `Continuous7Days` tier |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, 400 RU/s, and empty. You load it yourself, so the restore point you capture sits after a write you made |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The SDK examples use `AzureCliCredential` to select the identity from your `az login` session. Microsoft Entra ID authentication is the recommended approach for new accounts.

> [!NOTE]
> A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

This exercise creates billable resources. The `Continuous7Days` tier has no backup storage charge, but the account itself, its provisioned throughput, and the restore operation are billable. Complete the cleanup task when you finish.

## Task 1: Load the catalog and capture a restore point

1. Create the console project and add the packages.

    ```bash
    dotnet new console -o catalog-recovery
    cd catalog-recovery
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Newtonsoft.Json
    dotnet add package Azure.Identity
    ```

    `Microsoft.Azure.Cosmos` requires an explicit `Newtonsoft.Json` reference. Without it, the build fails with a message naming the missing package rather than a problem in your code.

1. Replace the contents of `Program.cs` with the following code. Replace `<cosmos-endpoint>` with the account endpoint the setup script printed.

    ```csharp
    using System.Net;
    using System.Text.Json;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";

    const string DataUrl = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product";
    const string ItemId = "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238";
    const string CategoryId = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F";

    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Container container = client.GetContainer("cosmicworks", "product");

    string command = args.Length > 0 ? args[0] : "count";

    switch (command)
    {
        case "seed":
        {
            using HttpClient http = new();
            string json = await http.GetStringAsync(DataUrl);
            List<Product> products = JsonSerializer.Deserialize<List<Product>>(json)!;

            foreach (Product product in products)
            {
                await container.UpsertItemAsync(product, new PartitionKey(product.categoryId));
            }

            Console.WriteLine($"Loaded {products.Count} products.");
            break;
        }

        case "read":
        {
            try
            {
                ItemResponse<Product> response =
                    await container.ReadItemAsync<Product>(ItemId, new PartitionKey(CategoryId));
                Console.WriteLine($"Found {response.Resource.name} priced at {response.Resource.price}.");
            }
            catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
            {
                Console.WriteLine("The item was not found.");
            }
            break;
        }

        case "delete":
        {
            await container.DeleteItemAsync<Product>(ItemId, new PartitionKey(CategoryId));
            Console.WriteLine("Deleted the item.");
            break;
        }

        default:
        {
            FeedResponse<int> counted = await container
                .GetItemQueryIterator<int>("SELECT VALUE COUNT(1) FROM c")
                .ReadNextAsync();
            Console.WriteLine($"Item count: {counted.First()}");
            break;
        }
    }

    public record Tag(string id, string name);

    public record Product(
        string id,
        string categoryId,
        string categoryName,
        string sku,
        string name,
        string description,
        decimal price,
        List<Tag> tags);
    ```

1. Load the catalog.

    ```bash
    dotnet run seed
    ```

    The command reports `Loaded 295 products.`

1. Read the product you recover later, and confirm the count.

    ```bash
    dotnet run read
    dotnet run count
    ```

    The read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` and the count reports 295.

1. Ask the service how far its backups reach, and record the value. This timestamp is your restore point.

    ```azurecli
    az cosmosdb sql retrieve-latest-backup-time `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --container-name "product" `
        --location $location
    ```

    The response contains a `latestRestorableTimestamp`. Convert it to the ISO 8601 UTC form the restore command expects, for example `2026-09-06T14:10:00Z`, and keep it available.

    If the command reports a timestamp earlier than your seeding, wait a minute and run it again. Backups catch up asynchronously, and restoring to a point before the writes landed recovers an empty container.

## Task 2: Delete the data and restore it into the same account

1. Delete the product, then confirm it's gone.

    ```bash
    dotnet run delete
    dotnet run read
    ```

    The read now reports `The item was not found.`

1. Delete the container that held it, simulating a broader accidental operation.

    ```azurecli
    az cosmosdb sql container delete `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --database-name "cosmicworks" `
        --name "product" `
        --yes
    ```

1. Find the account's instance identifier, which the enumeration commands need.

    ```azurecli
    az cosmosdb restorable-database-account list --account-name $accountName
    ```

    Copy the `name` value from the response. It's a GUID, and it isn't the account name.

1. List the restorable databases to get the database's resource identifier.

    ```azurecli
    az cosmosdb sql restorable-database list `
        --instance-id "<instance-id>" `
        --location $location
    ```

    Find the entry for `cosmicworks` and copy its `ownerResourceId`.

1. List the container events and locate the deletion you just performed.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id "<instance-id>" `
        --database-rid "<owner-resource-id>" `
        --location $location
    ```

    The response includes an event with an `operationType` of `Delete` and an `eventTimestamp`. Choose a timestamp when the container existed in the account's current write region and its data was backed up, within the retention window and before deletion. The verified post-seed timestamp from Task 1 meets these conditions and predates both deletions.

1. Restore the container into the same account, targeting the timestamp from Task 1.

    ```azurecli
    az cosmosdb sql container restore `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --name "product" `
        --restore-timestamp "<restore-timestamp>" `
        --disable-ttl True
    ```

    The container has no time-to-live policy, so `--disable-ttl True` changes nothing here. Include it as a habit: restoring a container that does have an expiry policy can delete the recovered items almost immediately.

    The restore takes a few minutes. The container reports a status of `Creating` while it runs.

1. Verify that both the container and the deleted product came back.

    ```bash
    dotnet run count
    dotnet run read
    ```

    The count reports 295 and the read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` One restore recovered both losses, because the restore point predates both the item deletion and the container deletion.

    The account-scoped data-plane role assignment the setup script made continues to apply after this same-account restore. If either command fails with an authorization error, check the error details, your signed-in identity, and its data-plane role assignment. Also check the account's network access settings. Each command starts a new SDK client, so it doesn't reuse session or continuation tokens from the earlier run.

## Task 3: Test the boundary that same-account restore doesn't cross

Same-account restore recovers deleted resources. Confirm what it refuses to do, so you know which restore target a real incident needs.

1. Attempt a same-account restore of the container that now exists.

    ```azurecli
    az cosmosdb sql container restore `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --name "product" `
        --restore-timestamp "<restore-timestamp>" `
        --disable-ttl True
    ```

    The service rejects the operation. Record the message you receive. Same-account restore recovers deleted resources only: it doesn't roll back a live container to an earlier state and it doesn't overwrite one.

1. Consider what the alternative costs. To recover a live container holding wrong data, you restore into a new account with `az cosmosdb restore`, then reconcile the recovered data back into production yourself. That path creates a second billable account, takes considerably longer, and charges a restore fee based on the volume of data restored. Don't run it in this exercise.

1. Review the restore in the account's activity log. In the Azure portal, open the account, select **Activity log**, and filter on **InAccount Restore Deleted**. The entry names the principal that started the restore, which is the evidence an incident review asks for.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources. If your lab provided `ResourceGroup1`, keep the group and use the account-deletion command instead.

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

Deleting the resource group removes the account, the database, the container, and the data-plane role assignment together. If your lab provided the group, or it holds other resources, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

You enabled continuous backup, captured a verified restore point, recovered a deleted container and the item inside it, and confirmed the boundary that decides which restore target a real incident needs.
