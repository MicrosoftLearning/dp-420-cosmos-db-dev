---
lab:
  title: Mirror an Azure Cosmos DB database and query it in Microsoft Fabric
  module: Module 20 - Implement Operational Analytics With Microsoft Fabric
  description: Grant the custom role mirroring needs, mirror a database into Microsoft Fabric, read the replication status, query the mirrored tables with T-SQL including nested JSON, watch a change replicate, and read the same tables from Spark.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Mirror an Azure Cosmos DB database and query it in Microsoft Fabric

In this exercise, you mirror an Azure Cosmos DB for NoSQL database into Microsoft Fabric and query the replicated copy. You grant Fabric the one permission no built-in role provides, create the mirrored database, read the replication status, run T-SQL aggregates and nested-JSON expansions against the mirrored tables, watch a single edit in Azure Cosmos DB reach the analytical copy, and finish by reading the same tables from a Spark notebook.

The account this exercise creates is configured for continuous backup, because mirroring requires it. That setting can't be turned off once it's on, which is why the exercise builds its own account and deletes it at the end.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

This exercise also requires:

- An active **Microsoft Fabric capacity**, a workspace assigned to that capacity, and the **admin** or **member** role in the workspace. If you don't have a capacity, [start a Fabric trial](/fabric/fundamentals/fabric-trial). The shared script doesn't create a Fabric capacity or workspace.
- The same Microsoft Entra ID account signed in to both the Azure CLI and the Fabric portal, because Fabric connects to Azure Cosmos DB as that identity.

No local runtime is needed. Every step runs in the Azure CLI, the Azure portal, or the Fabric portal.

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

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab20a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, key-based authentication disabled, one write region, public access for all networks, and a `Continuous` backup policy at the `Continuous7Days` tier |
| `cosmicworks` database | Holds both containers this exercise mirrors |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `customer` container | Partitioned on `/customerId`, autoscale up to 1,000 RU/s, loaded with 282 CosmicWorks documents: 10 customers and 272 sales orders |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#9888; Use a dedicated lab account. Continuous backup can't be disabled after enablement. Setup doesn't migrate backup mode or remove network restrictions from existing accounts. Never point this exercise at a shared training or production account. If your environment requires private networking, stop and resolve that setup separately before continuing.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Verify the Cosmos DB setup before creating the Fabric connection.

    ```powershell
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile mirroring
    ```

    Continue only when the checks pass. In Data Explorer, confirm 295 items in `cosmicworks/product` and 282 in `cosmicworks/customer` with `SELECT VALUE COUNT(1) FROM c`. A rerun preserves existing containers and doesn't remove extra items. Resolve any difference from these starting counts before continuing.

## Task 1: Grant Fabric permission to read analytics

Fabric connects to the source account as your Microsoft Entra ID identity, and it needs two data actions: `readMetadata` and `readAnalytics`. The Cosmos DB Built-in Data Contributor role the setup script assigned covers the first and not the second, and no built-in role covers `readAnalytics` at all. In this task, you define a custom role that grants both and assign it to yourself.

1. In the same terminal, build the role definition and write it to a file. Replace `<subscription-id>` with your own subscription ID, which `az account show --query id --output tsv` prints.

    ```powershell
    $subscriptionId = "<subscription-id>"
    $scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$accountName"

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
        --body "@mirroring-role.json"
    ```

    > &#10071; Keep the quotation marks around `"@mirroring-role.json"`. Passing the definition from a file avoids shell quoting problems with inline JSON, and `@` is a PowerShell special character.

1. Read back the ID of the role you created.

    ```azurecli
    az cosmosdb sql role definition list `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --query "[?roleName=='CosmosMirroringReader'].id | [0]" `
        --output tsv
    ```

1. Store that value and your own principal ID, then create the assignment.

    ```powershell
    $roleId = "<role-definition-id>"
    $principalId = az ad signed-in-user show --query id --output tsv
    ```

    ```azurecli
    az cosmosdb sql role assignment create `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --role-definition-id $roleId `
        --principal-id $principalId `
        --scope $scope
    ```

1. Confirm the assignment exists.

    ```azurecli
    az cosmosdb sql role assignment list `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --query "[].{principal:principalId, role:roleDefinitionId}" `
        --output table
    ```

    Confirm both assignments target your identity: the Built-in Data Contributor role from setup and the custom role you added. Other assignments can also appear on a reused account.

1. Verify the account-scoped permissions for your signed-in identity.

    ```powershell
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile mirroring -CheckMirroringPermissions
    ```

    This command checks the assigned role definitions for `readMetadata` and `readAnalytics`. It doesn't test the Fabric connection or replication.

> &#128221; A new role assignment takes a few minutes to propagate. If Fabric reports an authorization problem in the next task, wait a moment and try again.

## Task 2: Create the mirrored database in Fabric

Now connect Fabric to the account and start replication. Everything in this task happens in the Fabric portal.

1. In a browser, open the [Fabric portal](https://fabric.microsoft.com/) and sign in with the same identity you used for `az login`.

1. Open an existing workspace assigned to your active Fabric capacity, or create and assign a new workspace. You need the **admin** or **member** role in it.

1. Select **Create**, find the **Data Warehouse** section, and select **Mirrored Azure Cosmos DB**.

1. Enter `cosmicworks-mirror` as the name and select **Create**.

1. In the **New connection** section, select **Azure Cosmos DB for NoSQL** and provide the following values.

    | Setting | Value |
    | :--- | :--- |
    | **Azure Cosmos DB endpoint** | The account endpoint you recorded, for example `https://<your-account-name>.documents.azure.com:443/` |
    | **Connection name** | `dp420lab20-cosmos` |
    | **Authentication kind** | **Organizational account** |

    Selecting **Organizational account** is what makes Fabric connect as your Microsoft Entra ID identity, using the custom role from Task 1. The account has key-based authentication disabled, so **Account key** isn't an option here.

1. Select **Connect**.

1. Select the `cosmicworks` database, and leave both containers selected.

1. Select **Mirror database**.

Replication starts, and Fabric moves you to the replication status view.

## Task 3: Read the replication status

Before trusting any query result, confirm the copy is healthy and complete. In this task, you read the status view and interpret both of its numeric columns.

1. In the mirrored database, open **Monitor replication** if the view isn't already open.

1. Wait two to five minutes, refreshing occasionally. Transient errors during the first minutes are expected and clear on their own.

1. Confirm the database-level status reaches **Running**, and that both tables show **Running** as well.

1. Read the **Rows replicated** column for each table once the initial snapshot finishes. It should show 295 for the product container and 282 for the customer container.

1. Note the **Last completed** timestamp on each table.

    This column advances only when the source container changes. Both containers hold only what the setup script wrote to them, so this timestamp stops moving and stays where it is. That behavior is a healthy mirror with nothing to do, not a stalled one. You verify that reading in Task 5.

1. Select **View**, then **Source database**, to open the read-only Azure Cosmos DB data explorer, then return to the mirrored database.

    > &#128221; Reads from this source view are routed to Azure and consume request units on your account. Queries against the SQL analytics endpoint or lakehouse shortcuts read the replicated copy in OneLake and don't consume source request units.

## Task 4: Query the mirrored data with T-SQL

With replication running, the data is available as warehouse tables. In this task, you run an aggregate across the product catalog, then expand a nested JSON array two different ways and compare the row counts.

1. In the mirrored database, switch the experience selector from **Mirrored Azure Cosmos DB** to **SQL analytics endpoint**.

1. Expand the **Schemas**, then **dbo**, then **Tables** node, and note the names of the two tables. Each container appears as one table, and the documented naming pattern prefixes the container name with the source database name. Use the names you see in the following queries.

1. Open the context menu for the product table, select **New SQL query**, and run an aggregate across the catalog.

    ```sql
    SELECT
        categoryName,
        COUNT(*) AS productCount,
        AVG(price) AS averagePrice
    FROM
        cosmicworks_product
    GROUP BY
        categoryName
    ORDER BY
        productCount DESC
    ```

    The query returns 37 rows, one per category, with `Bikes, Road Bikes` at the top with 43 products.

1. Confirm that nested data arrives as text rather than structure.

    ```sql
    SELECT TOP 5 name, tags FROM cosmicworks_product
    ```

    The `tags` column holds a JSON string, not a set of columns.

1. Expand that array with `OPENJSON` and `CROSS APPLY`, declaring the shape of each element.

    ```sql
    SELECT
        COUNT(*) AS tagRows
    FROM
        cosmicworks_product AS p
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

1. Run the same query with `OUTER APPLY` instead.

    ```sql
    SELECT
        COUNT(*) AS tagRows
    FROM
        cosmicworks_product AS p
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

    The difference is 45, which is exactly the number of products carrying an empty `tags` array. `CROSS APPLY` drops them; `OUTER APPLY` keeps them with null tag columns. A catalog listing built on the first query silently loses 45 products.

1. Query the customer table and see what mirroring does with a container holding two document types.

    ```sql
    SELECT
        type,
        COUNT(*) AS documentCount
    FROM
        cosmicworks_customer
    GROUP BY
        type
    ```

    ```output
    type          documentCount
    ----------    -------------
    customer                 10
    salesOrder              272
    ```

1. Confirm that the table is the union of both shapes.

    ```sql
    SELECT TOP 10
        type, firstName, emailAddress, orderDate, salesOrderCount
    FROM
        cosmicworks_customer
    ORDER BY
        type
    ```

    Customer rows carry values in `firstName`, `emailAddress`, and `salesOrderCount` and null in `orderDate`. Sales order rows do the opposite. Nothing is wrong: the table faithfully represents a container that was never a single schema.

## Task 5: Watch a change reach the mirror

Mirroring replicates inserts, updates, and deletes continuously. In this task, you make one edit in Azure Cosmos DB and watch the status view and the query results follow it.

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

1. Return to the Fabric portal and open **Monitor replication** on the mirrored database.

1. Refresh the view until the **Last completed** timestamp for the product table advances and **Rows replicated** increases.

    The timestamp moved because the source changed. That advance is the behavior Task 3 predicted, and it's the evidence that separates a stalled mirror from an idle one.

1. Switch to the SQL analytics endpoint and confirm the new item is present.

    ```sql
    SELECT name, price, categoryName
    FROM cosmicworks_product
    WHERE id = 'dp420lab20-sample'
    ```

    ```output
    name                  price    categoryName
    -------------------   ------   -----------------
    Mirroring Test Bike   999.99   Bikes, Road Bikes
    ```

    Replication latency varies with the size and rate of changes, so how long this takes on your run depends on your capacity and region. If the row hasn't appeared yet, wait and query again rather than restarting replication.

1. Re-run the `OUTER APPLY` count from Task 4.

    It now returns 813 rather than 812, because the item you added carries an empty `tags` array and `OUTER APPLY` keeps it.

## Task 6: Query the mirrored data with Spark

The same Delta files that back the SQL analytics endpoint are readable by Spark, with no Cosmos DB connector involved. In this task, you point a lakehouse at them with a shortcut and query them from a notebook.

1. In the Fabric portal, return to your workspace and select **Create**.

1. In the **Data Engineering** section, select **Lakehouse**, name it `cosmicworks_lake`, and select **Create**.

1. Select **Get data**, then **New shortcut**, then **Microsoft OneLake**.

1. Select the `cosmicworks-mirror` mirrored database, select both tables, select **Next**, and then select **Create**.

    A shortcut is a pointer, not a copy. This step duplicates no data.

1. Open the context menu for the product table and select **New notebook**.

1. In the first cell, read the table into a dataframe and display it.

    ```python
    df = spark.sql("SELECT * FROM cosmicworks_product LIMIT 1000")
    display(df)
    ```

1. Run the same aggregate you ran in T-SQL, to confirm both engines read the same data.

    ```python
    summary = spark.sql("""
        SELECT categoryName, COUNT(*) AS productCount
        FROM cosmicworks_product
        GROUP BY categoryName
        ORDER BY productCount DESC
    """)
    display(summary)
    ```

    The top row is `Bikes, Road Bikes` with 44 products, one more than the 43 you saw in Task 4, because the item you added in Task 5 is in that category.

1. Confirm that nested data is a string column here too.

    ```python
    spark.sql("SELECT name, tags FROM cosmicworks_product LIMIT 5").show(truncate=False)
    ```

    Spark shows `tags` as text, exactly as the SQL analytics endpoint did. Expanding it in Spark uses Spark's own JSON functions rather than `OPENJSON`, because the engine differs even though the files don't.

## Clean up resources

This exercise creates resources in Azure and Fabric. Remove only the resources you created for it.

1. In the Fabric portal, delete the notebook, `cosmicworks_lake` lakehouse, and `cosmicworks-mirror` mirrored database you created. Remove the `dp420lab20-cosmos` connection only if nothing else uses it. Delete the workspace only if you created it for this exercise and it contains nothing you need to keep. If you started a Fabric trial for this exercise and no longer need it, cancel the trial as well.

1. Delete the Azure resource group only if you created it for this exercise and it contains no resources you need to keep:

    ```azurecli
    az group delete --name $resourceGroup --yes --no-wait
    ```

1. If the lab supplies the resource group, or the group contains other resources, keep the group. In the Azure portal, delete only the disposable Cosmos DB account created for this exercise.

Delete the Fabric items before the Azure resources. A mirrored database whose source account no longer exists reports a replication failure rather than removing itself.

You mirrored an operational database into an analytics platform without writing a line of transformation code, answered a category-level aggregate that would compete for request units on the source, and read the same replicated files from two different engines. The nested-array counts are the part worth remembering: 767 against 812 is the whole difference between `CROSS APPLY` and `OUTER APPLY`, and it's the kind of quiet 45-row loss that a report never reports.
