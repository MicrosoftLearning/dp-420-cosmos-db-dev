---
lab:
  title: Optimize an indexing strategy in C#
  module: Module 12 - Design and Optimize an Indexing Strategy in Azure Cosmos DB
  description: Measure a baseline, trim an indexing policy, add a composite index, and create a global secondary index, comparing the request charge after each change.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you tune the indexing on a product catalog and measure what each change costs. You start by recording a baseline for three operations, then trim the indexing policy, add a composite index, and finally create a global secondary index that turns a cross-partition lookup into a single-partition one.

Every task ends with a request charge you can compare against the one before it. Those numbers are the point of the exercise, so record them as you go.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path.

Global secondary indexes require continuous backup on the account, and moving an account to continuous backup can't be undone, which is why this exercise provisions an account of its own rather than changing a shared one.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab12 -LabProfile indexing
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab12a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, continuous backup at the `Continuous7Days` tier, with key-based authentication disabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#9888; Use only the account this script creates for this exercise. Later steps change the account's indexing configuration. Never point this exercise at a shared training or production account.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

1. Set variables for the account name and your subscription so the Azure CLI commands in this exercise can use them.

    ```powershell
    $accountName = "<your-account-name>"
    $subscriptionId = (az account show --query id --output tsv)
    ```

## Task 1: Measure the baseline

Before changing anything, record what three representative operations cost against the default indexing policy: a lookup by stock keeping unit, a sorted listing within one category, and a single item replace.

1. In the terminal, create a project folder and a console application.

    ```powershell
    mkdir indexing-lab
    cd indexing-lab
    dotnet new console
    ```

1. Add the three packages the application needs. `Microsoft.Azure.Cosmos` requires an explicit `Newtonsoft.Json` reference, and the project doesn't build without it.

    ```powershell
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Azure.Identity
    dotnet add package Newtonsoft.Json
    ```

1. Open **Program.cs**, delete its contents, and add the following code. Replace `<cosmos-endpoint>` with the account endpoint you recorded.

    ```csharp
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string categoryId = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F";
    string sku = "BK-R93R-44";
    string productId = "FD48A179-6CF5-45F2-8605-9DA19B9D4409";

    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Container product = client.GetDatabase("cosmicworks").GetContainer("product");

    await MeasureAsync(product, "sku lookup",
        "SELECT * FROM c WHERE c.sku = @sku",
        ("@sku", sku));

    await MeasureAsync(product, "category sorted by price",
        "SELECT * FROM c WHERE c.categoryId = @categoryId ORDER BY c.price DESC",
        ("@categoryId", categoryId));

    ItemResponse<Product> read = await product.ReadItemAsync<Product>(productId, new PartitionKey(categoryId));
    ItemResponse<Product> written = await product.ReplaceItemAsync(read.Resource, productId, new PartitionKey(categoryId));
    Console.WriteLine($"replace one product      : {written.RequestCharge,8:0.00} RU");

    static async Task MeasureAsync(Container container, string label, string text, params (string Name, object Value)[] parameters)
    {
        QueryDefinition query = new(text);
        foreach ((string name, object value) in parameters)
        {
            query = query.WithParameter(name, value);
        }

        double charge = 0;
        int items = 0;

        FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(query);
        while (iterator.HasMoreResults)
        {
            FeedResponse<Product> page = await iterator.ReadNextAsync();
            charge += page.RequestCharge;
            items += page.Count;
        }

        Console.WriteLine($"{label,-25}: {charge,8:0.00} RU for {items} items");
    }

    public class Product
    {
        public string id { get; set; } = "";
        public string categoryId { get; set; } = "";
        public string categoryName { get; set; } = "";
        public string sku { get; set; } = "";
        public string name { get; set; } = "";
        public string description { get; set; } = "";
        public decimal price { get; set; }
        public Tag[] tags { get; set; } = [];
    }

    public class Tag
    {
        public string id { get; set; } = "";
        public string name { get; set; } = "";
    }
    ```

1. Run the application.

    ```powershell
    dotnet run
    ```

    The output reports one charge per operation. Charges depend on the data, query shape, indexing policy, and consistency level. Record your measurements rather than the sample values.

    ```output
    sku lookup               :     3.03 RU for 1 items
    category sorted by price :    14.75 RU for 43 items
    replace one product      :    10.29 RU
    ```

The sorted query runs today because the range index that the default policy provides already serves an `ORDER BY` on a single property. Sorting on two properties is different: that clause always needs a composite index and fails without one. You make that change in Task 3.

## Task 2: Trim the indexing policy

The catalog's `description` and `tags` properties are read constantly and never filtered. Excluding them from the index cuts the cost of every write without affecting any query the storefront runs.

1. Create a file named **index-policy.json** in your project folder with the following content.

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" }
      ],
      "excludedPaths": [
        { "path": "/description/?" },
        { "path": "/tags/*" },
        { "path": "/\"_etag\"/?" }
      ]
    }
    ```

1. Apply the policy to the `product` container.

    ```azurecli
    az cosmosdb sql container update `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name cosmicworks `
        --name product `
        --idx @index-policy.json
    ```

1. Confirm the container now reports the excluded paths.

    ```azurecli
    az cosmosdb sql container show `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name cosmicworks `
        --name product `
        --query "resource.indexingPolicy.excludedPaths"
    ```

1. Run the application again and compare the replace charge with the baseline. Removing index paths takes effect immediately, so the write is cheaper on this run.

    ```powershell
    dotnet run
    ```

The two query charges stay close to their baselines, because neither query filters on the paths you excluded. That contrast is the result to take away: you paid less for writes and gave up nothing on reads.

## Task 3: Add a composite index

This task sorts the listing on two properties, `categoryId` and then `price`. An `ORDER BY` clause on two properties needs a composite index, so you define the index first and then point the application at the wider clause.

1. Edit **index-policy.json** to add a composite index on `categoryId` ascending and `price` descending, matching the `ORDER BY` clause you're about to write.

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" }
      ],
      "excludedPaths": [
        { "path": "/description/?" },
        { "path": "/tags/*" },
        { "path": "/\"_etag\"/?" }
      ],
      "compositeIndexes": [
        [
          { "path": "/categoryId", "order": "ascending" },
          { "path": "/price", "order": "descending" }
        ]
      ]
    }
    ```

1. Apply the updated policy.

    ```azurecli
    az cosmosdb sql container update `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name cosmicworks `
        --name product `
        --idx @index-policy.json
    ```

1. Adding an index path starts an index transformation, and the composite index isn't usable until that transformation finishes. Add this check immediately after the code that gets the `product` container, before any measurements.

    ```csharp
    ContainerResponse indexingResponse = await product.ReadContainerAsync(
        new ContainerRequestOptions { PopulateQuotaInfo = true });
    int indexProgress = int.Parse(
        indexingResponse.Headers["x-ms-documentdb-collection-index-transformation-progress"]);
    Console.WriteLine($"Index transformation: {indexProgress}%");
    if (indexProgress < 100)
    {
        return;
    }
    ```

1. Run the application. Repeat until the progress reports **100%**. The check stops the application while the transformation is incomplete.

1. Confirm the requested composite index definition. This command shows the policy, not the index transformation progress.

    ```azurecli
    az cosmosdb sql container show `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name cosmicworks `
        --name product `
        --query "resource.indexingPolicy.compositeIndexes"
    ```

1. To sort on both properties, change the query in the application so that it matches the composite index you defined.

    In **Program.cs**, replace the `ORDER BY c.price DESC` clause in the second `MeasureAsync` call with `ORDER BY c.categoryId, c.price DESC`.

1. Run the application again and compare the charge for the sorted query. Record the replace charge from this run as the baseline for Task 4.

With only 295 items, the charge difference can be small. Without the composite index, that two-property `ORDER BY` returns an error instead of results, so the index is what makes the query possible at all. Composite indexes can reduce query charges on larger datasets, particularly when the sorted property has many distinct values. Use your measurements to assess the saving.

## Task 4: Create a global secondary index

The stock keeping unit lookup is the query that partitioning can't help, because `sku` isn't the partition key. Give it a global secondary index partitioned on `/sku`.

### Enable the feature on the account

1. Create a file named **capabilities.json** with the following content. The property carries the feature's former name, and setting it enables global secondary indexes.

    ```json
    {
      "properties": {
        "enableMaterializedViews": true
      }
    }
    ```

1. Build the account's resource ID and enable the feature.

    ```azurecli
    $accountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$accountName"

    az rest `
        --method PATCH `
        --uri "https://management.azure.com$accountId/?api-version=2022-11-15-preview" `
        --body "@capabilities.json"
    ```

1. Confirm the feature is enabled.

    ```azurecli
    az rest `
        --method GET `
        --uri "https://management.azure.com$accountId/?api-version=2022-11-15-preview" `
        --query "properties.enableMaterializedViews"
    ```

    ```output
    true
    ```

### Create the index container

1. Create a file named **gsi-definition.json** with the following content. Change `West US 2` if you used a different region.

    ```json
    {
      "location": "West US 2",
      "tags": {},
      "properties": {
        "resource": {
          "id": "productBySku",
          "partitionKey": {
            "paths": [ "/sku" ]
          },
          "materializedViewDefinition": {
            "sourceCollectionId": "product",
            "definition": "SELECT c.id, c.sku, c.name, c.price, c.categoryId FROM c"
          }
        },
        "options": {
          "autoscaleSettings": {
            "maxThroughput": 1000
          }
        }
      }
    }
    ```

1. Create the index container.

    ```azurecli
    az rest `
        --method PUT `
        --uri "https://management.azure.com$accountId/sqlDatabases/cosmicworks/containers/productBySku/?api-version=2022-11-15-preview" `
        --body "@gsi-definition.json" `
        --headers content-type=application/json
    ```

1. Check the container creation status. This management response doesn't confirm that the initial data synchronization is complete. An empty status isn't a readiness signal.

    ```azurecli
    az rest `
        --method GET `
        --uri "https://management.azure.com$accountId/sqlDatabases/cosmicworks/containers/productBySku/?api-version=2022-11-15-preview" `
        --query "{status: properties.Status}"
    ```

1. Confirm the index container exists.

    ```azurecli
    az cosmosdb sql container show `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name cosmicworks `
        --name productBySku `
        --query "resource.id"
    ```

1. In the Azure portal, open **Metrics** for the account and select **Global Secondary Index Propagation Latency in Seconds**. Filter **GlobalSecondaryIndexName** to `productBySku`, then apply splitting by **GlobalSecondaryIndexStatus**. Wait for the index to report **Active**, rather than only **InitialBuildAfterCreate**. Missing metric data doesn't confirm readiness.

1. In **Data Explorer**, run this query in both `product` and `productBySku`. Continue only when both return **295**.

    ```sql
    SELECT VALUE COUNT(1) FROM c
    ```

### Compare the lookup

1. Add the following code so the application runs the same stock keeping unit query against the index container.

    Insert these two lines after the existing `MeasureAsync` calls and before the `ReadItemAsync` call.

    ```csharp
    Container productBySku = client.GetDatabase("cosmicworks").GetContainer("productBySku");

    await MeasureAsync(productBySku, "sku lookup on the index",
        "SELECT * FROM c WHERE c.sku = @sku",
        ("@sku", sku));
    ```

1. Run the application one more time and compare the two stock keeping unit lookups.

    The query against `product` visits every physical partition. The query against `productBySku` filters on that container's partition key, so it targets one partition. At this dataset size, both containers can fit on one physical partition, so a lower charge isn't guaranteed. The index avoids the added fan-out cost as the source gains physical partitions, but total query cost still depends on the data and results. Its smaller projection can also affect the comparison.

1. Compare the replace charge with the value you recorded at the end of Task 3, after the composite index finished building. Using that baseline keeps the source indexing policy the same for the comparison. A source container with a global secondary index incurs an extra replace charge because it persists both versions of the item so the change can propagate. That surcharge is part of the cost of avoiding cross-partition lookups.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab provided `ResourceGroup1`, or the group holds other resources, keep the group. In the Azure portal, delete only the Azure Cosmos DB account you created for this exercise.

The three numbers to keep from this exercise are the write charge before and after you trimmed the policy, the two stock keeping unit lookups, and the write charge after the index existed. Together they describe the whole trade: indexing costs writes and saves reads, and a global secondary index moves that trade to a different partition key rather than escaping it.
