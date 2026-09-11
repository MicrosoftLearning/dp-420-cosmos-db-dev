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

In this exercise, you build the fleet structure end to end. You create a fleet, add a fleetspace with a shared throughput pool, enroll two Azure Cosmos DB accounts into it, read the pool's throughput and the dedicated-versus-pooled split in Azure Monitor, and send fleet analytics to an Azure Data Lake Storage Gen2 account.

Two things about the shape of this exercise are worth knowing before you start. Resource and fleet management use the control plane, but seeding the accounts and creating the storage filesystem use data-plane operations. You don't write application code, but the setup script requires PowerShell 7 and the Azure CLI. And the accounts you enroll are idle lab accounts, so nothing draws from the pool. What you can observe is where the evidence lives and what each number means, which is what you need when the accounts aren't idle.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

This exercise runs no local application code, so no .NET or Python installation is required.

> &#9888; A throughput pool has a minimum of 100,000 RU/s, and an idle pool is billed at its minimum for every hour and every region it covers. That charge is far more than any other resource in this course. Complete the exercise in one sitting, and delete the fleetspace as soon as you finish Task 5 rather than leaving it in place.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB accounts and deletes them at the end, so it doesn't use the shared account from the rest of this learning path. A fleet groups accounts, so this profile creates two of them rather than one.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI and follow the interactive prompts. On Windows, the CLI uses Web Account Manager by default.

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

1. Wait for the script to finish. This profile creates two accounts one after the other, so it takes 10-20 minutes to run, longer than the other exercises in this course.

1. Record both **Account name** values the script prints. You need them in Task 3.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Two Azure Cosmos DB accounts | API for NoSQL, single-region write in your chosen region, with key-based authentication disabled |
| `cosmicworks` database | Created in each account |
| `product` container | Created in each account, partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor on each account, granted to your signed-in identity |

Both accounts are created with an identical single-region configuration on purpose. Accounts can share a throughput pool only when their regions and their write configuration match, so two accounts that differ in either respect can't be enrolled in the same fleetspace.

> &#10071; Fleets are available in a subset of Azure regions. When you create the fleet in Task 1, use a region the portal offers in its **Region** list. The fleet's region is independent of where your accounts live, so it doesn't have to match `$location`.

> &#9888; Use only the accounts this script creates for this exercise. Never point this exercise at a shared training or production account.

## Task 1: Create the fleet

The fleet is the top-level resource. It holds no configuration of its own, so creating it is quick, and everything else in this exercise is created inside it.

1. Sign in to the [Azure portal](https://portal.azure.com).

1. Enter *Cosmos DB fleet* in the global search bar, and then select **Azure Cosmos DB Fleets** under **Services**.

1. Select **+ Create**.

1. On the **Basics** pane, configure the following options:

    | Setting | Value |
    | :--- | :--- |
    | **Subscription** | Your Azure subscription |
    | **Resource group** | `ResourceGroup1` |
    | **Fleet Name** | A globally unique name, such as `dp420fleet` plus a few random characters |
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

The fleetspace decides which accounts can be grouped together and whether they share throughput. Two of its settings, the write-region type and the regions, are permanent once the fleetspace exists, so read them before you select **Ok**.

1. In the Azure portal, open the fleet you created.

1. Select **Fleetspaces** in the **Fleet resources** section of the resource menu.

1. Configure the following options in the dialog:

    | Setting | Value |
    | :--- | :--- |
    | **Fleetspace name** | `contoso-westus2` |
    | **Enable throughput pooling** | Selected |
    | **Select regions for accounts in throughput pool** | Add the same region you passed as `$location` |
    | **Select write-region type for accounts in throughput pool** | **Single-write region** (General purpose) |
    | **Throughput pool minimum RU/s** | `100000` |
    | **Throughput pool maximum RU/s** | `100000` |

1. Select **Ok**.

The minimum and the maximum are set to the same value here to keep the exercise's cost predictable. In a real deployment, you set a maximum up to 10 times the minimum, so the pool can scale into demand, and you're billed for the highest value it reaches in each hour.

The write-region type is what the fleetspace calls a service tier. **Single-write region** maps to `GeneralPurpose`, and **Multi-write region** maps to `BusinessCritical`. Both accounts from the setup script are single-region write accounts, which is why this exercise selects the first option.

## Task 3: Enroll both accounts in the fleetspace

Enrolling an account registers it with the fleetspace. It doesn't move data, change the account's endpoint, or interrupt anything running against it.

1. In the fleet's resource menu, select **Database accounts** in the **Fleet resources** section.

1. Select the `contoso-westus2` fleetspace in the **Fleetspace** section.

1. Enable the **Browse accounts to add to this fleetspace** option.

1. Select the first account the setup script created, and then select **+ Add to fleetspace**.

1. Repeat the previous step for the second account.

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

1. Try to add one of the accounts to the fleetspace a second time. The portal doesn't offer it, because an account belongs to exactly one fleetspace and one fleet. Moving an account elsewhere means deleting its fleetspace account registration first.

## Task 4: Read the pool and the dedicated throughput split

The pool is now configured, and both accounts can draw from it. This task locates the two places that report on it.

1. In the fleet's resource menu, open the **Metrics** page.

1. Select the `FleetspaceAutoscaledThroughput` metric.

    The chart reports the RU/s the pool scaled to, which is the quantity you're billed for. With no load on either account, it sits at the pool minimum of 100,000 RU/s. The pool minimum is the cost of an idle pool, and it's the number that makes pool sizing a decision rather than a formality.

1. Open one of the two Azure Cosmos DB accounts in the portal, and then open its **Metrics** page.

1. Select the **Total Requests** metric, filter to the `cosmicworks` database and the `product` container, and apply splitting by **Capacity Type**.

    This split separates requests served from the container's own dedicated throughput from requests served out of the pool. A resource always spends its dedicated allowance first and reaches for the pool only when it exceeds that allowance.

1. Select the **Total Request Units** metric and split it by **Capacity Type** as well.

    This chart answers the same question in request units rather than request counts, which is the form to use when you're deciding whether a pool is earning its minimum.

1. Expect no pooled consumption from these idle accounts. A time range that includes setup can show the seed requests under dedicated capacity. During an interval with no requests, the charts might show zero values or no data.

    That result is correct rather than a failure. The `product` container is provisioned at autoscale up to 1,000 RU/s and receives no traffic, so it never exceeds its dedicated allowance and never draws from the pool. In production, a sustained pooled share of zero means the dedicated allowances are already large enough and the pool isn't paying for itself.

## Task 5: Send fleet analytics to a storage account

Fleet analytics writes hourly usage, configuration, and cost data for every account in the fleet to a destination you own. This task configures a Data Lake Storage Gen2 destination and grants the write permission it needs.

1. Create a storage account with the hierarchical namespace enabled. Fleet analytics requires the hierarchical namespace, and enabling it after the account exists takes a one-way migration.

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

    Allow a few minutes for the assignment to propagate. If filesystem creation reports an authorization failure, confirm this principal and scope and retry after propagation. Don't switch to account keys to bypass the test.

1. Create a container in the storage account for the exported tables.

    ```azurecli
    az storage fs create `
        --name "fleetanalytics" `
        --account-name $storageAccountName `
        --auth-mode login
    ```

1. In the Azure portal, return to the fleet and select **Fleet analytics** in the **Monitoring** section of the resource menu.

1. Select **Add destination**.

1. Select **Send to storage account**, choose the storage account you created and the `fleetanalytics` container, and then save the destination.

1. Open the storage account, and then open its **Access Control (IAM)** page.

1. Select **Add role assignment**, and then select the **Storage Blob Data Contributor** role.

1. Select **+ Select members**, search for the shared **Cosmos DB Fleet Analytics** service principal, select it, and then select **Review + assign**.

    Skipping this step is the most common reason no data appears. The destination saves successfully without it, and then nothing is ever written.

1. Note that data takes up to an hour to start arriving, so the container is most likely still empty when you finish this exercise. If more than 24 hours pass with no data, the missing role assignment is the first thing to check.

When data does arrive, it lands as Delta Lake tables named for the schema: `FactRequestHourly`, `FactResourceUsageHourly`, `FactAccountHourly`, `FactMeterUsageHourly`, `FactFleetHourly`, and the dimension tables that give them meaning, including `DimResource` and `DimMeter`.

## Clean up resources

Delete the fleetspace first. It carries the throughput pool, which is billed on its minimum for every hour it exists, so removing it stops the largest charge in this exercise immediately.

1. In the fleet's resource menu, select **Database accounts**, and delete both fleetspace account registrations.

1. Select **Fleetspaces**, and delete the `contoso-westus2` fleetspace.

1. Delete the resource group only if you created it for this exercise and it contains only this exercise's resources. This deletion removes the fleet, both Azure Cosmos DB accounts, and the storage account. If your lab provided `ResourceGroup1`, keep the group and delete those resources individually in the Azure portal instead.

    ```azurecli
    az group delete --name $resourceGroup --yes --no-wait
    ```

1. Confirm in the portal that the exercise's resources are gone. If your lab provided the resource group, confirm that the group still exists.

This exercise deletes its own resources rather than leaving them until the end of the course, because a throughput pool is billed continuously whether or not anything uses it.
