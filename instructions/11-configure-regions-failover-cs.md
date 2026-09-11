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

In this exercise, you configure an Azure Cosmos DB for NoSQL account that spans two regions, move its write region while both regions are healthy, enable writes in both regions, and finally take a region offline the way you would during a real outage. Each step is verified against the account's own region topology rather than against an assumption about it.

The account this exercise creates is disposable, which matters more here than in any other exercise in this learning path. The last task takes a region offline, and **a region that goes offline stays offline until Microsoft brings it back**, which can take days and needs a support request after a drill. Running that against an account you care about would be a genuine outage.

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

1. Set variables for the resource group and the account's first region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab11 -LabProfile multiregion
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab11a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name**, **Account endpoint**, and **Second region** values the script prints. You need all three later in this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set variables for the account name and the second region so the Azure CLI commands in this exercise can use them.

    ```powershell
    $accountName = "<your-account-name>"
    $secondRegion = "<your-second-region>"
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, in two regions, with key-based authentication disabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The programs use `AzureCliCredential` to authenticate as the identity from your `az login` session.

> [!WARNING]
> Use only the account this script creates for this exercise. Later steps change the write region and then take a region offline. Never point this exercise at a shared training or production account.

> [!NOTE]
> A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Read the account's region topology

Every operation in this exercise changes the account's region topology, so you need a way to read it before you change anything. The account's `writeLocations` and `readLocations` properties are that source of truth.

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

The account replicates to two regions and accepts writes in one of them. That's the single-write-region topology, and the next task moves the write region within it.

## Task 2: Change the write region

Both regions are healthy, so this change is the planned operation: the service replicates outstanding changes before promoting the new region, and no data is lost. In the Azure CLI, moving failover priority `0` to another region performs the change.

1. Promote the second region to write region by giving it priority `0`.

    ```azurecli
    az cosmosdb failover-priority-change `
        --name $accountName `
        --resource-group $resourceGroup `
        --failover-policies "$secondRegion=0" "$location=1"
    ```

    The command lists every region on the account, assigns a unique priority to each, and gives exactly one of them `0`. Leaving a region out fails.

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

    `Microsoft.Azure.Cosmos` needs an explicit `Newtonsoft.Json` reference. Without it, the project doesn't build.

1. Replace the contents of the program file with the following code, then set the endpoint and the preferred region to the values you recorded.

    ```csharp
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string preferredRegion = "<your-second-region>";

    CosmosClientOptions options = new()
    {
        ApplicationPreferredRegions = new List<string> { preferredRegion }
    };

    CosmosClient client = new(endpoint, new AzureCliCredential(), options);
    Container container = client.GetContainer("cosmicworks", "product");

    PartitionKey partitionKey = new("AE48F0AA-4F65-4734-A4CF-D48B8F82267F");

    ItemResponse<dynamic> read = await container.ReadItemAsync<dynamic>(
        "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238", partitionKey);

    Console.WriteLine($"Read {read.Resource.name} for {read.RequestCharge} RU.");

    dynamic item = read.Resource;
    item.name = "Road-350-W Yellow, 48 (regional check)";

    ItemResponse<dynamic> write = await container.UpsertItemAsync(item, partitionKey);

    Console.WriteLine($"Write succeeded with status {(int)write.StatusCode}.");

    ItemResponse<dynamic> verified = await container.ReadItemAsync<dynamic>(
        "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238", partitionKey);

    Console.WriteLine($"Read back {verified.Resource.name}.");
    ```

    ```powershell
    dotnet run
    ```

    Both operations succeed. The client never named a write region: it read the account configuration, found the current write region, and routed the write there.

## Task 3: Enable writes in both regions

A single-write-region account concentrates every write in one place. Enabling multi-region writes makes both regions writable and removes the account-level failover requirement for writes entirely.

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

1. Change the preferred region in your program to the region you passed as `-Location`, so the client writes to the region it isn't currently pointed at, and run it again. The write succeeds against that region rather than being forwarded, which is the change multi-region writes makes.

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

    The container was created without a conflict resolution policy, so it carries the default: last writer wins on the system timestamp. Changing that requires creating a new container, because the policy is fixed at creation.

> [!NOTE]
> This exercise doesn't produce an actual write conflict. A conflict needs two regions to change the same item inside the replication window, which isn't reliably reproducible from a single machine. What you can verify is the policy that would resolve one, which is the configuration a production account depends on.

## Task 4: Take a region offline

This is the outage operation. Every step so far is reversible in minutes; this task isn't. Read the whole task before running the first command.

> [!WARNING]
> A region taken offline stays offline until Microsoft brings it back, which can take several days, and a region taken offline for a drill needs a support request to restore. Only run this against the disposable account this exercise created, which you delete in the next section.

1. Take the account's first region offline, simulating a regional outage.

    ```azurecli
    az cosmosdb offline-region `
        --name $accountName `
        --resource-group $resourceGroup `
        --region $location
    ```

1. Confirm the account is now serving from one region.

    ```azurecli
    az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query "{write:writeLocations[].locationName, read:readLocations[].locationName}"
    ```

    ```output
    {
      "read": [ "<your-second-region>" ],
      "write": [ "<your-second-region>" ]
    }
    ```

1. Leave the program's preferred region set to the first region from Task 3, and run it again without changing the code. The SDK discovers the remaining healthy region and routes reads and writes there.

    Had the offline region been the only write region and the account been configured with a single write region, this command would have promoted the read region with the highest failover priority to write region instead. Either way, the application recovers without a code change.

1. Open the account in the [Azure portal](https://portal.azure.com), select **Replicate data globally**, and confirm the offline region is shown as offline. The **Replicate data globally** pane is also where the **Offline region**, **Change write region**, and **Configure failover policy** operations live in the portal.

You've now run all three account-level responses to a regional problem: a planned write region change, a topology change that removes the need for one, and an outage response.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab provided `ResourceGroup1`, or the group holds other resources, keep the group. In the Azure portal, delete only the Azure Cosmos DB account you created for this exercise.

Deleting the account is what stops the two-region charge. A two-region account bills throughput and storage in both regions, and multi-region writes cost more per unit of throughput than a single write region. An account left running after this exercise costs more than twice what a single-region account does.
