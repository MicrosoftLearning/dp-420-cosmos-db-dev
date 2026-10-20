---
lab:
  title: Create and Monitor a Fleet
  module: Module 15 - Manage Azure Cosmos DB at Scale with Fleets
  description: Create a fleet and a pooled fleetspace, enroll two Azure Cosmos DB accounts, read pool and dedicated throughput in Azure Monitor, and send fleet analytics to Data Lake Storage Gen2.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Create and Monitor a Fleet

In this exercise, you create a fleet and a fleetspace with a shared throughput pool, enroll two Azure Cosmos DB accounts, inspect throughput metrics in Azure Monitor, and configure fleet analytics to export to Azure Data Lake Storage Gen2.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

This exercise runs no local application code, so no .NET or Python installation is required.

> &#9888; This exercise configures a 10,000-RU/s throughput pool. An idle pool is billed at its configured minimum for every hour and every region it covers. Complete the exercise in one sitting, and delete the fleetspace as soon as you finish Task 5.

## Set up your Azure Cosmos DB resources

The setup script creates two dedicated Azure Cosmos DB accounts for this exercise. Delete them during cleanup rather than leaving them in the shared course environment.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI and follow the interactive prompts.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab15 -LabProfile fleet
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds them for you by adding six random characters to the prefix, giving names like `dp420lab15a7f3k9`.

1. Wait for the script to finish. Creating and seeding both accounts usually takes 10-20 minutes.

1. Record both **Account name** values the script prints. You need them in Task 3.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Two Azure Cosmos DB accounts | API for NoSQL, single-region write in your chosen region, with key-based authentication disabled |
| `cosmicworks` database | Created in each account |
| `product` container | Created in each account, partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor on each account, granted to your signed-in identity |

Both accounts use the same region and write configuration, as required to share a throughput pool.

> &#10071; Fleets are available in a subset of Azure regions. When you create the fleet in Task 1, use a region the portal offers in its **Region** list. The fleet's region is independent of where your accounts live, so it doesn't have to match `$location`.

> &#9888; Use only the accounts this script creates for this exercise. Never point this exercise at a shared training or production account.

## Task 1: Create the fleet

Create a fleet to organize the two accounts into a fleetspace.

1. Sign in to the [Azure portal](https://portal.azure.com).

1. Enter *Cosmos DB fleet* in the global search bar, and then select **Azure Cosmos DB Fleets** under **Services**.

1. Select **+ Create**.

1. On the **Basics** pane, configure the following options:

    | Setting | Value |
    | :--- | :--- |
    | **Subscription** | Your Azure subscription |
    | **Resource group** | `ResourceGroup1` |
    | **Fleet Name** | A unique name, such as `dp420fleet` plus 6 random characters |
    | **Region** | A region offered in the list |

1. Select **Review + create**, wait for validation to succeed, and then select **Create**.

1. Return to the terminal and confirm the fleet exists.

    ```azurecli
    az cosmosdb fleet list `
        --resource-group $resourceGroup `
        --query "[].{name:name, location:location}" `
        --output table
    ```

    The command lists the fleet you created:

    ```output
    Name         Location
    -----------  ----------
    dp420fleet   westus2
    ```

## Task 2: Add a fleetspace with a throughput pool

A fleetspace groups accounts that can share throughput. Its service tier and regions can't be changed after creation, so check both before you select **Ok**.

1. In the Azure portal, open the fleet you created.

1. Select **Fleetspaces** in the **Fleet resources** section of the resource menu.

1. Select **+ New fleetspace** to open the configuration dialog.

1. Configure the following options in the dialog:

    | Setting | Value |
    | :--- | :--- |
    | **Fleetspace name** | `contoso-westus2` |
    | **Select region(s) for accounts in fleetspace** | Choose the same region as the two Azure Cosmos DB accounts created during setup (**West US 2** if you used the default `$location`), then select **Add** |
    | **Select service tier for accounts in fleetspace** | **General purpose** |
    | **Enable throughput pooling** | Selected |
    | **Throughput pool minimum RU/s** | `10000` |
    | **Throughput pool maximum RU/s** | `10000` |

1. Confirm that the region list contains only the region of your two Azure Cosmos DB accounts, then select **Ok**.

Setting the minimum and maximum to the same value keeps the pool's capacity fixed. For a scaling pool, the maximum can be up to 10 times the minimum. Billing is based on the highest throughput reached in each hour, per region.

The **General purpose** service tier (`GeneralPurpose`) is for accounts with one write region, which can also have additional read regions. **Business critical** (`BusinessCritical`) is for accounts with multi-region writes. Accounts sharing a throughput pool must have the same region set and write mode. Both accounts from the setup script use a single write region, so select **General purpose**. See the [fleet pool configuration rules](https://learn.microsoft.com/azure/cosmos-db/fleet-pools#configuration-rules).

## Task 3: Enroll both accounts in the fleetspace

Enrollment registers an existing account with the fleetspace without moving its data or changing its endpoint.

1. In the fleet's resource menu, select **Database accounts** in the **Fleet resources** section.

1. Select the `contoso-westus2` fleetspace in the **Fleetspace** section.

1. Enable the **Browse accounts to add to this fleetspace** option.

1. Select both accounts the setup script created, then select **+ Add to fleetspace**.

1. Return to the terminal and list the registrations, substituting the fleet name you chose in Task 1.

    ```azurecli
    az cosmosdb fleetspace account list `
        --resource-group $resourceGroup `
        --fleet-name "<your-fleet-name>" `
        --fleetspace-name "contoso-westus2" `
        --query "[].name" `
        --output tsv
    ```

    Two rows come back, one per enrolled account.

## Task 4: Read the pool and the dedicated throughput split

Use fleet metrics to inspect pool capacity and account metrics to compare dedicated and pooled consumption.

1. In the fleet's resource menu, under **Monitoring**, open the **Metrics** page.

1. Select **Fleetspace Autoscaled Throughput (Preview)** and set **Aggregation** to **Max**.

1. Set the time range to **Last hour** and the time granularity to **5 minutes**. Use **Add filter** to select the `contoso-westus2` fleetspace for `FleetspaceName` and your accounts' region for `Region`.

    With the pool minimum and maximum both set to 10,000 RU/s, look for a value of **10,000 RU/s**. This is scaled pool capacity, not throughput consumed by the accounts. An idle pool is billed at its configured minimum.

1. Open one of the two Azure Cosmos DB accounts in the portal, and then open its **Monitoring** > **Metrics** page.

1. Select the **Total Requests** metric, filter to the `cosmicworks` database and the `product` container, and apply splitting by **Capacity Type**.

    This split separates requests served by dedicated throughput from those served by the pool. Resources consume dedicated RU/s first, then use the pool when demand exceeds that allocation.

1. Select the **Total Request Units** metric and split it by **Capacity Type** as well.

    This metric shows request units consumed from each capacity type rather than the number of requests.

1. Expect no pooled consumption from these idle accounts. A time range that includes setup can show the seed requests under dedicated capacity. During an interval with no requests, the charts might show zero values or no data.

    For a production workload, compare dedicated and pooled usage over a representative period before adjusting the pool size.

## Task 5: Send fleet analytics to a storage account

Fleet analytics exports hourly usage, configuration, and cost data. Configure a Data Lake Storage Gen2 destination and grant the analytics service permission to write to it.

1. Create a Data Lake Storage Gen2 account with the hierarchical namespace enabled.

    ```azurecli
    az storage account create `
        --name "dp420fleet$(Get-Random -Maximum 99999)" `
        --resource-group $resourceGroup `
        --location $location `
        --sku Standard_LRS `
        --enable-hierarchical-namespace true
    ```

1. Record the generated storage account name from the command output.

1. Grant your signed-in identity permission to create the filesystem. An Azure management role, including Owner, doesn't grant storage data access. This assignment is separate from the Fleet Analytics service principal's assignment later in this task.

    ```powershell
    $storageAccountName = "<your-storage-account-name>"
    $storageAccountId = az storage account show --name $storageAccountName --resource-group $resourceGroup --query id --output tsv
    $principalId = az ad signed-in-user show --query id --output tsv
    ```

    ```azurecli
    az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type User `
        --role "Storage Blob Data Contributor" `
        --scope $storageAccountId
    ```

    If filesystem creation returns an authorization error, allow a few minutes for the role assignment to take effect, then retry.

1. Create a container in the storage account for the exported tables.

    ```azurecli
    az storage fs create `
        --name "fleetanalytics" `
        --account-name $storageAccountName `
        --auth-mode login
    ```

1. In the Azure portal, return to the fleet and select **Fleet analytics** in the **Monitoring** section of the resource menu.

1. Select **Add destination**.

1. Enter a name for the destination.

1. Select **Send to storage account**, choose the storage account you created and the `fleetanalytics` container, and then save the destination.

1. Open the storage account, and then open its **Access Control (IAM)** page.

1. Select **Add role assignment**, and then select the **Storage Blob Data Contributor** role.

1. Select **+ Select members**, search for the shared **Cosmos DB Fleet Analytics** service principal, select it, and then select **Review + assign**.

1. Fleet analytics can take up to an hour to begin exporting. You don't need to wait for exported files before cleanup.

Exports use Delta Lake tables, including `FactRequestHourly`, `FactResourceUsageHourly`, `FactAccountHourly`, `FactMeterUsageHourly`, `FactFleetHourly`, `DimResource`, and `DimMeter`.

## Clean up resources

Delete the account registrations and fleetspace before the remaining resources to stop ongoing throughput-pool charges.

1. In the fleet's resource menu, select **Database accounts**, and delete both fleetspace account registrations.

1. Select **Fleetspaces**, and delete the `contoso-westus2` fleetspace.

1. Delete the resource group only if you created it for this exercise and it contains only this exercise's resources. This deletion removes the fleet, both Azure Cosmos DB accounts, and the storage account. If your lab provided `ResourceGroup1`, keep the group and delete those resources individually in the Azure portal instead.

    ```azurecli
    az group delete --name $resourceGroup --yes --no-wait
    ```

1. Confirm in the portal that the exercise's resources are gone. If your lab provided the resource group, confirm that the group still exists.
