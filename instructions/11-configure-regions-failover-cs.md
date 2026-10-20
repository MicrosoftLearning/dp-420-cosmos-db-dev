---
lab:
  title: Configure Regions and Failover in C#
  module: Module 11 - Design Multi-Region Availability and Failover in Azure Cosmos DB
  description: Read the region topology of a two-region Azure Cosmos DB account, change its write region, enable multi-region writes, and take a region offline with a forced failover.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Configure Regions and Failover in C#

In this exercise, you configure a two-region Azure Cosmos DB for NoSQL account, change its write region, enable multi-region writes, and test availability by taking one region offline.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI. Complete the sign-in prompt, then select your lab subscription if prompted.

    ```azurecli
    az login
    ```

1. Set variables for the resource group and both account regions. Use `ResourceGroup1`, or the group supplied by your lab if its name differs. The example uses `westus2` and `westcentralus`; you can choose two different regions that support Azure Cosmos DB.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    $secondRegion = "westcentralus"
    ```

1. Run the setup script, passing your second region with `-SecondaryLocation`.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -SecondaryLocation $secondRegion -NamePrefix dp420lab11 -LabProfile multiregion
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab11a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both later in this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`. Confirm that **Second region** matches the value you set in `$secondRegion`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it. Keep the `$location` and `$secondRegion` values you set before setup.

    ```powershell
    $accountName = "<your-account-name>"
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, in two regions, with key-based authentication disabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The programs use `AzureCliCredential` to authenticate as the identity from your `az login` session.

> &#9888; Use only the account this script creates for this exercise. Later steps change the write region and then take a region offline. Never point this exercise at a shared training or production account.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Read the account's region topology

Before changing the account, view its configured write and read regions using the `writeLocations` and `readLocations` properties.

1. Show which region currently accepts writes, and the failover priority of every region.

    ```azurecli
    az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query "{writeRegion:writeLocations[].locationName, priorities:failoverPolicies[].{region:locationName, priority:failoverPriority}}"
    ```

    The output lists one write region and both regions with their priorities:

    ```output
    {
      "priorities": [
        { "priority": 0, "region": "West US 2" },
        { "priority": 1, "region": "<your-second-region>" }
      ],
      "writeRegion": [ "West US 2" ]
    }
    ```

1. Confirm that multi-region writes are switched off and that both regions serve reads.

    ```azurecli
    az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query "{multiRegionWrites:enableMultipleWriteLocations, readRegions:readLocations[].locationName}"
    ```

    ```output
    {
      "multiRegionWrites": false,
      "readRegions": [ "West US 2", "<your-second-region>" ]
    }
    ```

The account replicates data to both regions but accepts writes in only one.

## Task 2: Change the write region

Both regions are healthy, so you can change the write region without data loss. The region with failover priority `0` accepts writes.

1. Promote the second region to write region by giving it priority `0`.

    ```azurecli
    az cosmosdb failover-priority-change `
        --name $accountName `
        --resource-group $resourceGroup `
        --failover-policies "$secondRegion=0" "$location=1"
    ```

    List every account region with a unique failover priority, starting at `0`.

1. Confirm the promotion took effect.

    ```azurecli
    az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query "writeLocations[].locationName"
    ```

    ```output
    [
      "<your-second-region>"
    ]
    ```

1. Write an item and read it back, to confirm the account still accepts writes after the promotion. Create a folder for the application, and open it in a terminal.

    ```powershell
    dotnet new console -o region-check
    cd region-check
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Azure.Identity
    dotnet add package Newtonsoft.Json
    ```

1. In **Visual Studio Code**, open `Program.cs` in the `region-check` folder. Replace its contents with the following code, then set `endpoint` to the account endpoint you recorded.

    For `preferredRegion`, use the second region's display name from Task 1, such as `"West Central US"`. The .NET SDK also provides region constants, such as `Regions.WestCentralUS`, for these names.

    ```csharp
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string preferredRegion = "<your-second-region>";

    // Preferred regions control client routing, not account configuration.
    CosmosClientOptions options = new()
    {
        ApplicationPreferredRegions = new List<string> { preferredRegion }
    };

    // Use the identity from az login instead of an account key.
    CosmosClient client = new(endpoint, new AzureCliCredential(), options);
    Container container = client.GetContainer("cosmicworks", "product");

    // Together, the item ID and /categoryId value identify the product.
    PartitionKey partitionKey = new("AE48F0AA-4F65-4734-A4CF-D48B8F82267F");

    ItemResponse<dynamic> read = await container.ReadItemAsync<dynamic>(
        "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238", partitionKey);

    Console.WriteLine($"Read {read.Resource.name} for {read.RequestCharge} RU.");

    dynamic item = read.Resource;
    item.name = "Road-350-W Yellow, 48 (regional check)";

    // The SDK routes the write using the account's region configuration.
    ItemResponse<dynamic> write = await container.UpsertItemAsync<dynamic>(item, partitionKey);

    Console.WriteLine($"Write succeeded with status {(int)write.StatusCode}.");

    ItemResponse<dynamic> verified = await container.ReadItemAsync<dynamic>(
        "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238", partitionKey);

    Console.WriteLine($"Read back {verified.Resource.name}.");
    ```

1. Save `Program.cs`, then run it in the terminal from the `region-check` folder.

    ```powershell
    dotnet run
    ```

    Confirm that the write succeeds and the read returns the updated item name. The SDK discovers the current write region from the account configuration.

## Task 3: Enable writes in both regions

Multi-region writes let applications write to either region.

1. Enable multi-region writes on the account. Every read region becomes a read and write region.

    ```azurecli
    az cosmosdb update `
        --name $accountName `
        --resource-group $resourceGroup `
        --enable-multiple-write-locations true
    ```

1. Confirm both regions now accept writes.

    ```azurecli
    az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query "{multiRegionWrites:enableMultipleWriteLocations, writeRegions:writeLocations[].locationName}"
    ```

    ```output
    {
      "multiRegionWrites": true,
      "writeRegions": [ "<your-second-region>", "West US 2" ]
    }
    ```

1. In `Program.cs`, change `preferredRegion` from the second region to the account's original first region. If you used `$location = "westus2"` during setup, replace the `preferredRegion` line with:

    ```csharp
    string preferredRegion = Regions.WestUS2;
    ```

    If you chose a different first region, use its corresponding `Regions` constant or its display name from Task 1. Change only `preferredRegion`; keep `endpoint` unchanged.

1. Save `Program.cs`, then run it again from the `region-check` terminal.

    ```powershell
    dotnet run
    ```

    Confirm that the output includes `Write succeeded with status 200.` and the updated item name. Both regions are now writable, and the client prefers the first region.

1. Read the container's conflict resolution policy, which is the policy that now decides the outcome when both regions change the same item.

    ```azurecli
    az cosmosdb sql container show `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --database-name cosmicworks `
        --name product `
        --query "resource.conflictResolutionPolicy"
    ```

    ```output
    {
      "conflictResolutionPath": "/_ts",
      "conflictResolutionProcedure": "",
      "mode": "LastWriterWins"
    }
    ```

    The default policy resolves conflicts using the `_ts` system timestamp. Conflict resolution policies are set when the container is created.

## Task 4: Take a region offline

> &#9888; A region taken offline for a drill can remain offline for several days and requires a Microsoft support request to restore. Use only the disposable account created for this exercise.

1. Take the account's first region offline, simulating a regional outage.

    ```azurecli
    az cosmosdb offline-region `
        --name $accountName `
        --resource-group $resourceGroup `
        --region $location
    ```

1. Open the account in the [Azure portal](https://portal.azure.com) and select **Replicate data globally**. Select **Refresh** to update the region status.

    Before continuing, confirm the following in the **Status** column:

    - The first region, specified by `$location`, is **Offline**.
    - The second region, specified by `$secondRegion`, is **Online**.

    For the default setup, these are **West US 2** and **West Central US**, respectively. If the first region isn't marked **Offline** yet, wait and refresh again.

1. Without changing `Program.cs`, run it again from the `region-check` terminal.

    ```powershell
    dotnet run
    ```

    Confirm that the output includes `Write succeeded with status 200.` and the updated item name. The SDK routes requests to the healthy region even though `preferredRegion` still names the offline region.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab provided `ResourceGroup1`, or the group holds other resources, keep the group. In the Azure portal, delete only the Azure Cosmos DB account you created for this exercise.

Delete the account to stop ongoing charges. Throughput and storage are billed in both regions.
