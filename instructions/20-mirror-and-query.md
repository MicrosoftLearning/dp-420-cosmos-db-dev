---
lab:
  title: Mirror an Azure Cosmos DB database and query it in Microsoft Fabric
  module: Module 20 - Implement Operational Analytics With Microsoft Fabric
  description: Grant the custom role mirroring needs, mirror a database into Microsoft Fabric, read the replication status, query the mirrored tables with T-SQL including nested JSON, watch a change replicate, and read the same tables from Spark.
  duration: 60 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Mirror an Azure Cosmos DB database and query it in Microsoft Fabric

In this exercise, you mirror an Azure Cosmos DB for NoSQL database into Microsoft Fabric, query the mirrored data with T-SQL and Spark, and observe how source changes replicate. You also compare how `CROSS APPLY` and `OUTER APPLY` handle nested JSON arrays.

This exercise takes approximately **60** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

This exercise also requires:

- An active **Microsoft Fabric capacity** or **Fabric trial capacity**. If you don't have a capacity, [start a Fabric trial](/fabric/fundamentals/fabric-trial).
- Permission to create a workspace, or an administrator-provided workspace with the **admin** or **member** role.
- Permission to create **Mirrored Azure Cosmos DB** items. Your Fabric administrator must enable this feature and, if needed, allow you to start a Fabric trial.
- The same Microsoft Entra ID account signed in to both the Azure CLI and the Fabric portal, because Fabric connects to Azure Cosmos DB as that identity.

## Set up your Azure Cosmos DB resources

Use a dedicated Azure Cosmos DB account for this exercise rather than the shared account from the rest of this learning path.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI and follow the sign-in prompts.

    ```azurecli
    az login
    ```

1. Set variables for the resource group and region. Use the resource group supplied by your lab environment when one is provided. Otherwise, use a new group that contains only this exercise's resources. To avoid cross-region data transfer charges, use the same Azure region as your Fabric capacity when possible.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "eastus"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab20 -LabProfile mirroring
    ```

    The script appends six random characters to `dp420lab20` to create a unique account name, for example `dp420lab20a7f3k9`.

1. Wait 5-10 minutes for the script to finish.

1. Record the **Account name** and **Account endpoint** from the script output.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, key-based authentication disabled, one write region, public access for all networks, and a `Continuous` backup policy at the `Continuous7Days` tier |
| `cosmicworks` database | Holds both containers this exercise mirrors |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `customer` container | Partitioned on `/customerId`, autoscale up to 1,000 RU/s, loaded with 282 CosmicWorks documents: 10 customers and 272 sales orders |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

> &#9888; Don't use a shared training or production account. Mirroring requires continuous backup, which can't be disabled after enablement. This exercise also requires public network access for all networks; don't remove network restrictions from an existing account to run it.

1. Set `$accountName` to the account name from the script output.

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Verify the Cosmos DB setup before creating the Fabric connection.

    ```powershell
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile mirroring
    ```

    Confirm that all checks pass. In Data Explorer, use `SELECT VALUE COUNT(1) FROM c` to confirm 295 items in `cosmicworks/product` and 282 in `cosmicworks/customer` before continuing. Rerunning setup doesn't remove extra items.

## Task 1: Grant Fabric permission to read analytics

Fabric needs the `readMetadata` and `readAnalytics` data actions. The Cosmos DB Built-in Data Contributor role grants `readMetadata` but not `readAnalytics`. Create a custom role with both permissions and assign it to your signed-in identity.

Continue in the same PowerShell terminal.

1. Get the account's resource ID for the role scope, build the role definition, and write it to a file.

    ```powershell
    $scope = az cosmosdb show `
        --name $accountName `
        --resource-group $resourceGroup `
        --query id `
        --output tsv

    $roleDefinition = @{
        RoleName         = "CosmosMirroringReader"
        Type             = "CustomRole"
        AssignableScopes = @($scope)
        Permissions      = @(
            @{
                DataActions = @(
                    "Microsoft.DocumentDB/databaseAccounts/readMetadata",
                    "Microsoft.DocumentDB/databaseAccounts/readAnalytics"
                )
            }
        )
    }

    $roleDefinition | ConvertTo-Json -Depth 5 | Set-Content -Path mirroring-role.json -Encoding utf8
    ```

1. Create the role definition from that file.

    ```azurecli
    az cosmosdb sql role definition create `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --body "@mirroring-role.json" `
        --query "{Role:roleName,RoleId:name}" `
        --output table
    ```

1. Store the custom role's ID in `$roleId`.

    ```powershell
    $roleId = az cosmosdb sql role definition list `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --query "[?roleName=='CosmosMirroringReader'].id | [0]" `
        --output tsv
    ```

1. Assign the custom role to your signed-in user at account scope.

    ```powershell
    $principalId = az ad signed-in-user show --query id --output tsv

    az cosmosdb sql role assignment create `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --role-definition-id $roleId `
        --principal-id $principalId `
        --scope $scope `
        --query "{PrincipalId:principalId,RoleDefinitionId:roleDefinitionId,Scope:scope}" `
        --output table
    ```

1. Confirm both role assignments exist for your signed-in user.

    ```powershell
    az cosmosdb sql role assignment list `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --query "[?principalId=='$principalId'].{PrincipalId:principalId,RoleDefinitionId:roleDefinitionId,Scope:scope}" `
        --output table
    ```

    Confirm that the table includes the Built-in Data Contributor role and your custom role. The custom assignment's `RoleDefinitionId` should match `$roleId`, and its `Scope` should match `$scope`.

1. Verify the account-scoped permissions for your signed-in identity.

    ```powershell
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile mirroring -CheckMirroringPermissions
    ```

    Both `Signed-in user has account-scoped readMetadata` and `Signed-in user has account-scoped readAnalytics` must show `PASS` before you continue.

> &#128221; A new role assignment takes a few minutes to propagate. If Fabric reports an authorization problem in the next task, wait a moment and try again.

## Task 2: Create the mirrored database in Fabric

1. In a browser, open the [Fabric portal](https://fabric.microsoft.com/) and sign in with the same identity you used for `az login`.

1. Create a workspace for this exercise unless your Fabric administrator has provided one with the required Fabric or trial capacity and mirroring permissions.

    To create a workspace:

    1. Select **Workspaces** in the left navigation pane, then **New workspace**.
    1. Name it `dp420lab20cosmos` followed by six random lowercase letters or digits, for example `dp420lab20cosmosa7f3k9`.
    1. Assign it to your active Fabric or trial capacity and finish creating it.

    Open the workspace to continue.

1. In the workspace toolbar, select **+ New item**. In the **New item** pane, select **All items**, search for `Mirrored Azure Cosmos DB`, and select the **Mirrored Azure Cosmos DB** tile.

1. Under **New sources**, select **Azure Cosmos DB v2**.

1. On **New source**, enter the following connection settings.

    | Setting | Value |
    | :--- | :--- |
    | **Cosmos DB Endpoint** | The account endpoint you recorded, for example `https://<your-account-name>.documents.azure.com:443/` |
    | **Connection** | **Create new connection** |
    | **Connection name** | `dp420lab20-cosmos` |
    | **Authentication kind** | **Organizational account** |
    | **Privacy level** | **None** |

    Sign in with the Microsoft Entra ID account that received the custom role in Task 1.

1. Select **Connect**.

1. Select the `cosmicworks` database and select **Connect**.

1. On **Choose data**, confirm that `customer` and `product` are selected. Leave **Automatically mirror future tables** selected, then select **Connect**.

1. On **Destination**, enter `cosmicworks-mirror` for **Name** and select **Create mirrored database**.

Fabric opens the mirrored database with **Replication status** selected in **Explorer**.

## Task 3: Read the replication status

Confirm that both containers have finished their initial replication before querying the mirrored data.

1. In **Explorer**, select **Replication status** if it isn't already selected, then scroll down to **Monitor replication**.

1. Wait two to five minutes, selecting **Refresh** periodically. The table list may initially show **No data has landed**, even while the overall status is **Running**.

1. Confirm that the overall **Status** is **Running** and that the table list shows the following values.

    | Name | Status | Rows replicated |
    | :--- | :--- | ---: |
    | `[cosmicworks].[product]` | **Running** | 295 |
    | `[cosmicworks].[customer]` | **Running** | 282 |

1. Note the **Last completed** timestamp on each table.

    The timestamp advances when the source container changes. It can remain unchanged while the mirror is idle.

## Task 4: Query the mirrored data with T-SQL

Query the mirrored product catalog, then compare two ways to expand its nested JSON arrays.

1. In the mirrored database, switch the experience selector from **Mirrored database** to **SQL analytics endpoint**.

1. In **Explorer**, expand **cosmicworks-mirror**, then **Schemas**, then **cosmicworks**, then **Tables**. Confirm that the `customer` and `product` tables are listed.

1. On the **Home** toolbar, select **New SQL query** and run an aggregate across the catalog.

    ```sql
    SELECT
        categoryName,
        COUNT(*) AS productCount,
        AVG(price) AS averagePrice
    FROM
        [cosmicworks].[product]
    GROUP BY
        categoryName
    ORDER BY
        productCount DESC
    ```

    The query returns 37 rows, one per category, with `Bikes, Road Bikes` at the top with 43 products.

1. Replace the existing query with the following query and run it to inspect the `tags` column.

    ```sql
    SELECT TOP 5 name, tags FROM [cosmicworks].[product]
    ```

    The `tags` column holds a JSON string, not a set of columns.

1. Replace the existing query with the following query and run it to expand the `tags` array with `OPENJSON` and `CROSS APPLY`.

    ```sql
    SELECT
        COUNT(*) AS tagRows
    FROM
        [cosmicworks].[product] AS p
        CROSS APPLY OPENJSON(p.tags) WITH (
            tagId   varchar(100) '$.id',
            tagName varchar(100) '$.name'
        ) AS t
    ```

    ```output
    tagRows
    -------
    767
    ```

1. Replace the existing query with the following version, which uses `OUTER APPLY`, and run it.

    ```sql
    SELECT
        COUNT(*) AS tagRows
    FROM
        [cosmicworks].[product] AS p
        OUTER APPLY OPENJSON(p.tags) WITH (
            tagId   varchar(100) '$.id',
            tagName varchar(100) '$.name'
        ) AS t
    ```

    ```output
    tagRows
    -------
    812
    ```

    The 45 extra rows represent products with an empty `tags` array. `CROSS APPLY` excludes those products; `OUTER APPLY` keeps them with null tag columns.

1. Replace the existing query with the following query and run it to count each document type in the customer table.

    ```sql
    SELECT
        type,
        COUNT(*) AS documentCount
    FROM
        [cosmicworks].[customer]
    GROUP BY
        type
    ```

    ```output
    type          documentCount
    ----------    -------------
    customer                 10
    salesOrder              272
    ```

1. Replace the existing query with the following query and run it to compare the fields of the two document types.

    ```sql
    SELECT TOP 10
        type, firstName, emailAddress, orderDate, salesOrderCount
    FROM
        [cosmicworks].[customer]
    ORDER BY
        type
    ```

    Customer rows have values for `firstName`, `emailAddress`, and `salesOrderCount`; sales order rows have values for `orderDate`. Properties absent from a document appear as null.

## Task 5: Watch a change reach the mirror

Mirroring replicates inserts, updates, and deletes continuously. Add a document to the source and confirm that it appears in Fabric.

1. Record the product table's **Last completed** timestamp and **Rows replicated** count in **Monitor replication**.

1. In a separate browser tab, open the [Azure portal](https://portal.azure.com) and go to the Azure Cosmos DB account this exercise created.

1. Select **Data Explorer** in the resource menu, expand the `cosmicworks` database, expand the `product` container, and select **Items**.

1. Select **New Item**, replace the contents with the following document, and select **Save**.

    ```json
    {
      "id": "dp420lab20-sample",
      "categoryId": "AE48F0AA-4F65-4734-A4CF-D48B8F82267F",
      "categoryName": "Bikes, Road Bikes",
      "sku": "BK-LAB20",
      "name": "Mirroring Test Bike",
      "description": "An item created to observe replication into Microsoft Fabric.",
      "price": 999.99,
      "tags": []
    }
    ```

1. Return to the Fabric portal and switch to the **Mirrored database** view. In **Explorer**, select **Replication status** and scroll down to **Monitor replication**.

1. Refresh the view until the **Last completed** timestamp for the product table advances and **Rows replicated** increases. Allow a few minutes for the change to replicate.

1. Switch to the SQL analytics endpoint. Replace the existing query with the following query and run it to confirm that the new item is present.

    ```sql
    SELECT name, price, categoryName
    FROM [cosmicworks].[product]
    WHERE id = 'dp420lab20-sample'
    ```

    ```output
    name                  price    categoryName
    -------------------   ------   -----------------
    Mirroring Test Bike   999.99   Bikes, Road Bikes
    ```

    If the row hasn't appeared yet, wait a moment and run the query again.

1. Replace the existing query with the following `OUTER APPLY` count and run it.

    ```sql
    SELECT
        COUNT(*) AS tagRows
    FROM
        [cosmicworks].[product] AS p
        OUTER APPLY OPENJSON(p.tags) WITH (
            tagId   varchar(100) '$.id',
            tagName varchar(100) '$.name'
        ) AS t
    ```

    The count increases from 812 to 813 because `OUTER APPLY` includes the new product despite its empty `tags` array.

## Task 6: Query the mirrored data with Spark

Use OneLake shortcuts to make the mirrored Delta tables available in a lakehouse, then query them from a Spark notebook.

1. In the Fabric portal, return to your workspace and select **+ New item**.

1. In the **New item** pane, select **All items**, search for `Lakehouse`, and select the **Lakehouse** tile. Name it `cosmicworks_lake`, leave **Lakehouse schemas** enabled, and select **Create**.

1. In the lakehouse **Explorer**, expand **Tables**, open the context menu for **dbo**, and select **New table shortcut**. Select **Microsoft OneLake**.

1. Select the `cosmicworks-mirror` mirrored database, then select **Next**.

1. In **Connection method**, leave **Passthrough identity** selected and select **Connect**.

1. Under **Tables**, expand **cosmicworks** and select `customer` and `product`. Select **Next**, keep the shortcut names `customer` and `product`, and select **Create**.

    The shortcuts appear as `dbo.customer` and `dbo.product` in the lakehouse and reference the existing data without copying it.

1. Expand **Tables** to verify that the shortcuts for `customer` and `product` appear under `dbo`.

1. Return to your workspace and select **+ New item**. In the **New item** pane, select **All items**, search for `Notebook`, and select the **Notebook** tile.

1. In **New Notebook**, enter `cosmicworks_analysis` for **Name**, confirm that **Location** is the workspace you're using for this exercise, and select **Create**.

1. In **Explorer**, on the **Data items** tab, select **Add data items**, then **From OneLake catalog**.

1. Add the existing `cosmicworks_lake` lakehouse and set it as the notebook's default lakehouse.

1. In the first cell, keep **PySpark (Python)** selected and replace the sample comments with the following code. Select the run button to the left of the cell to preview the product table.

    ```python
    df = spark.sql("SELECT * FROM dbo.product LIMIT 1000")
    display(df)
    ```

1. Add a new code cell below the first one and run the following aggregate to confirm that Spark and T-SQL read the same data.

    ```python
    summary = spark.sql("""
        SELECT categoryName, COUNT(*) AS productCount
        FROM dbo.product
        GROUP BY categoryName
        ORDER BY productCount DESC
    """)
    display(summary)
    ```

    The top row is `Bikes, Road Bikes` with 44 products, one more than the 43 you saw in Task 4, because the item you added in Task 5 is in that category.

1. Add another code cell and run the following query to inspect the `tags` column.

    ```python
    spark.sql("SELECT name, tags FROM dbo.product LIMIT 5").show(truncate=False)
    ```

    The `tags` column also contains JSON text in Spark. Use Spark's JSON functions to expand it.

## Clean up resources

Remove only the resources you created for this exercise, starting with the Fabric items.

1. In the Fabric portal, delete the `cosmicworks_analysis` notebook, `cosmicworks_lake` lakehouse, and `cosmicworks-mirror` mirrored database you created. Remove the `dp420lab20-cosmos` connection only if nothing else uses it. Delete the workspace only if you created it for this exercise and it contains nothing you need to keep; keep any administrator-provided workspace. If you started a Fabric trial for this exercise and no longer need it, cancel the trial as well.

1. Delete the Azure resource group only if you created it for this exercise and it contains no resources you need to keep:

    ```azurecli
    az group delete --name $resourceGroup --yes --no-wait
    ```

1. If the lab supplies the resource group, or the group contains other resources, keep the group. In the Azure portal, delete only the disposable Cosmos DB account created for this exercise.

You mirrored Azure Cosmos DB data into Fabric, queried it with T-SQL and Spark, and observed a source change replicate. You also compared how `CROSS APPLY` and `OUTER APPLY` handle empty JSON arrays.
