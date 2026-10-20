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

# Recover from a recovery point in C#

In this exercise, you use continuous backup to recover a deleted Azure Cosmos DB container and its data. You load the CosmicWorks catalog, record a restore point, delete data, and restore it into the same account. You also test whether repeating the restore recovers a deleted item in an existing container.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

You also need the **CosmosRestoreOperator** role at subscription scope, or equivalent permissions, to discover restorable accounts and restore resources. See [restore permissions](/azure/cosmos-db/continuous-backup-restore-permissions).

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

The in-account restore commands need [Azure CLI](/cli/azure/install-azure-cli) version 2.65.0 or later.

## Set up your Azure Cosmos DB resources

This exercise creates a separate account with continuous backup. Delete this account at the end of the exercise.

> &#9888; Use only the account this script creates for this exercise. Later steps delete a container and then restore it. Never point this exercise at a shared training or production account.

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

    The output reports a `type` of `Continuous`, a `tier` of `Continuous7Days`, and a `migrationState` of `null`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled and continuous backup at the `Continuous7Days` tier |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, 400 RU/s, and initially empty |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The SDK examples use `AzureCliCredential` to select the identity from your `az login` session. Microsoft Entra ID authentication is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

This exercise creates billable resources. The `Continuous7Days` tier has no backup storage charge, but the account itself, its provisioned throughput, and the restore operation are billable. Complete the cleanup task when you finish.

## Task 1: Load the catalog and capture a restore point

1. In your Windows PowerShell terminal, create the console project and add the packages.

    ```powershell
    dotnet new console -o catalog-recovery
    cd catalog-recovery
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Newtonsoft.Json
    dotnet add package Azure.Identity
    ```

1. Replace the contents of `Program.cs` with the following code. Replace `<cosmos-endpoint>` with the account endpoint the setup script printed.

    ```csharp
    using System.Net;
    using System.Text.Json;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";

    const string DataUrl = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product";

    // Together, the item ID and /categoryId partition key value identify the
    // product used to verify recovery. An item ID alone isn't unique across partitions.
    const string ItemId = "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238";
    const string CategoryId = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F";

    // Use the identity from az login, not an account key.
    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Container container = client.GetContainer("cosmicworks", "product");

    string command = args.Length > 0 ? args[0] : "count";

    switch (command)
    {
        case "seed":
        {
            using HttpClient http = new();
            string json = await http.GetStringAsync(DataUrl);
            // Map the downloaded JSON to the record types defined below.
            List<Product> products = JsonSerializer.Deserialize<List<Product>>(json)!;

            // Upsert creates an item or replaces one with the same ID and partition key.
            // Pass each product's categoryId value because the container uses /categoryId.
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
                // A point read goes directly to the product's logical partition.
                // Resource contains the product deserialized from the SDK response.
                ItemResponse<Product> response =
                    await container.ReadItemAsync<Product>(ItemId, new PartitionKey(CategoryId));
                Console.WriteLine($"Found {response.Resource.name} priced at {response.Resource.price}.");
            }
            catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
            {
                // Report the expected result after deleting the item.
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
            // With no partition key filter, the count covers all category partitions.
            // SELECT VALUE returns an integer rather than a JSON object.
            FeedResponse<int> counted = await container
                .GetItemQueryIterator<int>("SELECT VALUE COUNT(1) FROM c")
                .ReadNextAsync();
            Console.WriteLine($"Item count: {counted.First()}");
            break;
        }
    }

    // Keep property names aligned with the catalog JSON for both deserialization
    // and SDK writes. These records preserve the product fields, including nested tags.
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

    The first command-line argument selects the operation:

    | Command | SDK behavior | Purpose in this exercise |
    | :--- | :--- | :--- |
    | `seed` | Downloads the catalog and upserts each product | Establishes the data to back up |
    | `read` | Reads one product by its item ID and partition key | Checks the product's name and price before deletion and after restore |
    | `delete` | Deletes only that product, not the container | Simulates the first accidental data loss |
    | `count` (or no argument) | Counts items across the container | Checks that the catalog contains 295 products before deletion and after restore |

    Run `seed` only for the initial load. Rerunning it after a restore would recreate missing products and could hide an incomplete recovery.

1. Load the catalog.

    ```powershell
    dotnet run seed
    ```

    The command reports `Loaded 295 products.`

1. Read the product you recover later, and confirm the count.

    ```powershell
    dotnet run read
    dotnet run count
    ```

    The read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` and the count reports 295.

1. Retrieve the latest restorable timestamp and record it as your restore point.

    ```azurecli
    az cosmosdb sql retrieve-latest-backup-time `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --container-name "product" `
        --location $location
    ```

    The response contains a `latestRestorableTimestamp`. Convert it to the ISO 8601 UTC form the restore command expects, for example `2026-09-06T14:10:00Z`, and keep it available.

    If the timestamp is earlier than the catalog load, wait a minute and run the command again.

## Task 2: Delete the data and restore it into the same account

1. Delete the product, then confirm it's gone.

    ```powershell
    dotnet run delete
    dotnet run read
    ```

    The read now reports `The item was not found.`

1. Delete the `product` container.

    ```azurecli
    az cosmosdb sql container delete `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --database-name "cosmicworks" `
        --name "product" `
        --yes
    ```

1. Find the account's instance identifier and save it in `$instanceId`.

    ```powershell
    $instanceId = az cosmosdb restorable-database-account list `
        --account-name $accountName `
        --query "[?deletionTime==null].name | [0]" `
        --output tsv
    ```

1. Find the `cosmicworks` database's resource identifier and save it in `$ownerResourceId`.

    ```powershell
    $ownerResourceId = az cosmosdb sql restorable-database list `
        --instance-id $instanceId `
        --location $location `
        --query "[?resource.ownerId=='cosmicworks'].resource.ownerResourceId | [0]" `
        --output tsv
    ```

1. List the container events and locate the deletion you just performed.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    Find the `product` row with **Operation** set to `Delete`. Confirm that its **EventTimeUTC** is later than the restore timestamp recorded in Task 1.

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

    > &#128221; The restore could take 5 minutes or more. The container reports a status of `Creating` while it runs. Wait for the restore to finish before running the verification commands in the next step.

    The `--disable-ttl True` option prevents time-to-live settings from deleting recovered items after the restore.

1. Verify that both the container and the deleted product came back.

    ```powershell
    dotnet run count
    dotnet run read
    ```

    The count reports 295 and the read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` One restore recovered both losses, because the restore point predates both the item deletion and the container deletion.

## Task 3: Test the limits of same-account restore

Same-account restore recovers deleted containers; it doesn't overwrite an existing container. Repeat the restore to check whether it recovers an item deleted from the restored container.

1. After the first restore has finished, list the container events again.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    Record the latest creation or recreation event's **EventTimeUTC** for `product`. You compare this history with the output after the second restore request.

1. Delete only the recovered product item, and confirm it's gone. Don't delete the container or run `seed`.

    ```powershell
    dotnet run delete
    dotnet run read
    ```

    The read reports `The item was not found.` The `product` container still exists.

1. Repeat the original restore command, using the same restore timestamp from Task 1.

    ```azurecli
    az cosmosdb sql container restore `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --name "product" `
        --restore-timestamp "<restore-timestamp>" `
        --disable-ttl True
    ```

    Wait for the command to finish before continuing.

1. List the container events again and compare them with the history you recorded.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    The recorded creation or recreation timestamp should be unchanged, with no additional creation or recreation event for `product`.

1. Read the deleted product again.

    ```powershell
    dotnet run read
    ```

    The read should still report `The item was not found.` The repeated restore hasn't recovered the item from the existing container.

1. For item-level recovery, you can restore to a new account with `az cosmosdb restore` and copy the required data back. This incurs additional charges; don't run it in this exercise.

1. In the Azure portal, open the account, select **Activity log**, and filter on **InAccount Restore Deleted**. Identify the principal that started the restore.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources. If your lab provided `ResourceGroup1`, keep the group and use the account-deletion command instead.

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab provided the group, or it holds other resources, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```
