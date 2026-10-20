---
lab:
  title: Tune a high-cost query in C#
  module: Module 13 - Analyze and Tune Query and Operation Performance in Azure Cosmos DB
  description: Baseline three operations against a product catalog, inspect query metrics for scan evidence, compare a direct property filter, add a composite index, and compare fan-out with single-partition routing.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Tune a high-cost query in C#

In this exercise, you measure request charges and query metrics for a product catalog. You then rewrite a filter, add a composite index, and compare queries with and without a partition-key filter.

Record your measurements after each task. Request charges vary with your data and query configuration, so your values might differ from the examples.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

## Set up your Azure Cosmos DB resources

The core exercises reuse an account prepared with the `core` profile, not the two-item account from the first portal exercise. Before skipping setup, open **Allfiles/Labs/Shared** in PowerShell, sign in with `az login`, and set `$resourceGroup`, `$location`, and `$accountName` to your recorded values. Run `./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile core` and continue only when it succeeds. In Data Explorer, confirm 295 items in `cosmicworks/product` and 237 in `cosmicworks/productMeta` with `SELECT VALUE COUNT(1) FROM c`.

If you have no verified core account, follow the setup steps below. To add missing resources to an existing lab account, pass its explicit `-AccountName` to setup rather than using a different module's name prefix. Reseeding restores canonical items but doesn't remove extra items or reset container policies. Resolve mismatches before continuing; don't reset a shared account automatically.

For a repeat of this exercise, inspect the product indexing policy before recording a baseline. If the composite index from a previous run is still present, record that fact or use a fresh core lab account. Don't treat the earlier optimized policy as the default baseline.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI and follow the sign-in prompts for your environment.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab13 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab13a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

Provisioned throughput values are in request units per second (RU/s). The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds every container this learning path uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with product categories and tags |
| `leases` container | Partitioned on `/id`, 400 RU/s, used by change feed exercises |
| `operations` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, left empty |
| `bulkload` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, left empty |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

## Task 1: Record a baseline

Measure three operations: a point read, a name lookup using case conversion, and a query that filters by category and price.

1. In the terminal, create a project folder and a console application.

    ```powershell
    mkdir query-tuning-lab
    cd query-tuning-lab
    dotnet new console
    ```

1. Add the three packages the application needs.

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
    string categoryId = "75BF1ACB-168D-469C-9AA3-1FD26BB4EA4C";
    string productId = "BD340F0A-F661-4ED8-B36F-FBA7623605D9";

    // Reuse one client authenticated by az login for all measurements.
    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Container product = client.GetDatabase("cosmicworks").GetContainer("product");

    // An ID plus partition key permits a point read without executing SQL.
    ItemResponse<Product> read = await product.ReadItemAsync<Product>(
        productId, new PartitionKey(categoryId));
    Console.WriteLine($"{"point read",-24}: {read.RequestCharge,8:0.00} RU  ({read.Resource.name})");

    await MeasureAsync(product, "UPPER(name) lookup",
        "SELECT * FROM c WHERE UPPER(CONCAT(c.name, '')) = @name",
        ("@name", "TOURING-3000 BLUE, 62"));

    await MeasureAsync(product, "category and price",
        "SELECT * FROM c WHERE c.categoryId = @categoryId AND c.price > @floor",
        ("@categoryId", categoryId), ("@floor", 1000));

    static async Task MeasureAsync(Container container, string label, string text,
        params (string Name, object Value)[] parameters)
    {
        // Bind values separately from SQL rather than interpolating them into it.
        QueryDefinition query = new(text);
        foreach ((string name, object value) in parameters)
        {
            query = query.WithParameter(name, value);
        }

        double charge = 0;
        int items = 0;

        // Include every result page when measuring the query's total RU charge.
        FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(query);
        while (iterator.HasMoreResults)
        {
            FeedResponse<Product> page = await iterator.ReadNextAsync();
            charge += page.RequestCharge;
            items += page.Count;
        }

        Console.WriteLine($"{label,-24}: {charge,8:0.00} RU for {items} items");
    }

    // Match the stored JSON property names when deserializing query results.
    public class Product
    {
        public string id { get; set; } = "";
        public string categoryId { get; set; } = "";
        public string categoryName { get; set; } = "";
        public string sku { get; set; } = "";
        public string name { get; set; } = "";
        public string description { get; set; } = "";
        public decimal price { get; set; }
    }
    ```

1. Run the application.

    ```powershell
    dotnet run
    ```

    The output reports one charge per operation, and the item counts confirm the queries match the data you expect.

    ```output
    point read              :     1.00 RU  (Touring-3000 Blue, 62)
    UPPER(name) lookup      :    12.86 RU for 1 items
    category and price      :     3.29 RU for 12 items
    ```

The point read is your reference for the same item and consistency level. A point read of a 1 KB item costs 1 request unit (RU) with session, consistent prefix, or eventual consistency. Strong and bounded staleness reads cost twice as much. Record the consistency level and all three charges before continuing.

## Task 2: Inspect the same queries with query metrics

The `UPPER(CONCAT(c.name, ''))` query returns one item. The server-side metrics reveal how many documents the engine loaded to produce that result.

1. In **Program.cs**, replace the entire `MeasureAsync` method with the following version. Leave the point read, both `MeasureAsync(...)` calls above the method, and the `Product` class unchanged.

    ```csharp
    static async Task MeasureAsync(Container container, string label, string text,
        params (string Name, object Value)[] parameters)
    {
        QueryDefinition query = new(text);
        foreach ((string name, object value) in parameters)
        {
            query = query.WithParameter(name, value);
        }

        double charge = 0;
        long retrieved = 0;
        long output = 0;

        FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(query);
        while (iterator.HasMoreResults)
        {
            FeedResponse<Product> page = await iterator.ReadNextAsync();
            charge += page.RequestCharge;

            // CumulativeMetrics aggregates the partition metrics for this page.
            var queryMetrics = page.Diagnostics.GetQueryMetrics();
            if (queryMetrics is null)
            {
                throw new InvalidOperationException("Query metrics weren't returned for this page.");
            }

            ServerSideMetrics metrics = queryMetrics.CumulativeMetrics;
            retrieved += metrics.RetrievedDocumentCount;
            output += metrics.OutputDocumentCount;
        }

        Console.WriteLine(
            $"{label,-24}: {charge,8:0.00} RU  retrieved {retrieved,4}  output {output,4}");
    }
    ```

1. Run the application again.

    ```powershell
    dotnet run
    ```

Example output:

```output
UPPER(name) lookup      :    12.86 RU  retrieved  295  output    1
category and price      :     3.29 RU  retrieved   12  output   12
```

1. Review the measurements:

    - **Retrieved** counts documents loaded by the engine; **output** counts documents returned. Retrieved greater than output is evidence of document loading that didn't contribute to the result.
    - The name query retrieves **295** documents but returns **1**, demonstrating a full-container document scan.
    - The category and price query retrieves and returns **12** documents.

Record both queries' retrieved counts, output counts, and request charges for comparison in Task 3.

## Task 3: Rewrite the filter so the index serves it

Direct property equality is an index-friendly alternative to the baseline expression. For this lookup, you know the exact stored product name, so you can compare it directly without converting its casing.

1. In **Program.cs**, replace only the `MeasureAsync(...)` call labeled `UPPER(name) lookup` with the following call. Leave the measurement method and the category and price query unchanged.

    ```csharp
    // Compare the indexed property directly, using the name's stored casing.
    await MeasureAsync(product, "direct name match",
        "SELECT * FROM c WHERE c.name = @name",
        ("@name", "Touring-3000 Blue, 62"));
    ```

1. Run `dotnet run` again. Confirm that the rewritten query still returns the same product, then compare its charge and retrieved count with your Task 2 measurements. Example output:

    ```output
    direct name match       :     2.87 RU  retrieved    1  output    1
    ```

The retrieved count drops from 295 to 1 and the request charge falls. The default policy already indexes `/name/?`, so this improvement requires no indexing policy change.

## Task 4: Add a composite index for the two-property filter

For the category and price query, retrieved 12 and output 12 indicate that the engine loaded only the documents it returned. A composite index can still help, because a query combining an equality filter with a range filter can be answered from a single composite index rather than by intersecting two range indexes.

1. In **Program.cs**, add the following import at the top of the file:

    ```csharp
    using System.Text.Json;
    ```

    Replace the iterator declaration in `MeasureAsync` with the following to turn on index metrics:

    ```csharp
    QueryRequestOptions options = new() { PopulateIndexMetrics = true };
    FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(query, requestOptions: options);
    ```

1. Inside the `while` loop in `MeasureAsync`, add the following code after updating `output` to print each page's index metrics:

    ```csharp
    if (!string.IsNullOrEmpty(page.IndexMetrics))
    {
        using JsonDocument indexMetrics = JsonDocument.Parse(page.IndexMetrics);
        Console.WriteLine($"\n{label} - index utilization");
        Console.WriteLine(JsonSerializer.Serialize(
            indexMetrics.RootElement,
            new JsonSerializerOptions { WriteIndented = true }));
    }
    ```

1. Run the application and read the index utilization section for `category and price`. Record which paths appear as utilized and whether any composite index appears under the potential section. Example output:

    ```output
    category and price - index utilization
    {
      "UtilizedIndexes": {
        "SingleIndexes": [
          {
            "IndexSpec": "/price/?",
            "IndexImpactScore": "High"
          },
          {
            "IndexSpec": "/categoryId/?",
            "IndexImpactScore": "High"
          }
        ],
        "CompositeIndexes": []
      },
      "PotentialIndexes": {
        "SingleIndexes": [],
        "CompositeIndexes": [
          {
            "IndexSpecs": [
              "/categoryId ASC",
              "/price ASC"
            ],
            "IndexImpactScore": "High"
          }
        ]
      }
    }
    ```

1. For a fresh core container with the default policy, create a file named **indexing-policy.json** in your project folder with the following content. The equality filter comes first and the range filter last, which is the ordering a composite index requires.

    If you reuse a customized policy, copy its current JSON from **Data Explorer** > **Settings** > **Indexing Policy** instead. Add the composite entry below only if it isn't already present. Preserve the other indexes and paths in that policy.

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        {
          "path": "/*"
        }
      ],
      "excludedPaths": [
        {
          "path": "/\"_etag\"/?"
        }
      ],
      "compositeIndexes": [
        [
          {
            "path": "/categoryId",
            "order": "ascending"
          },
          {
            "path": "/price",
            "order": "ascending"
          }
        ]
      ]
    }
    ```

1. Apply the policy to the `product` container.

    ```azurecli
    az cosmosdb sql container update `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --database-name cosmicworks `
        --name product `
        --idx '@indexing-policy.json'
    ```

1. In **Data Explorer**, open the `product` container's **Settings** and check the index transformation progress. Wait until the transformation completes, then run the application again and compare the request charge and index utilization against the baseline.

The container remains available for reads and writes during index transformation.

## Task 5: Compare fan-out with single-partition routing

The `product` container is partitioned on `/categoryId`. Every query so far that filtered on `categoryId` routed to one partition. This task runs the same price filter with and without that routing.

1. Replace the existing `MeasureAsync(...)` call labeled `category and price` with the following two calls. Keep the point read and the `direct name match` call unchanged.

    ```csharp
    // Without a partition-key equality filter, the query can visit every partition.
    await MeasureAsync(product, "price only (fan-out)",
        "SELECT * FROM c WHERE c.price > @floor",
        ("@floor", 1000));

    // Adding /categoryId equality restricts the query to that category's partition.
    await MeasureAsync(product, "price within category",
        "SELECT * FROM c WHERE c.categoryId = @categoryId AND c.price > @floor",
        ("@categoryId", categoryId), ("@floor", 1000));
    ```

1. Run the application and compare the two lines.

    ```output
    price only (fan-out)    :    10.44 RU  retrieved   86  output   86
    price within category   :     3.29 RU  retrieved   12  output   12
    ```

Both queries use indexes: retrieved and output counts are equal. The price-only query returns 86 products; the category-scoped query returns 12. If the container has one physical partition, the lower RU charge comes from returning fewer products. With multiple physical partitions, the category filter also avoids querying other physical partitions.

1. Print the partition key range IDs reached by each query. Add the following code inside the `while` loop in `MeasureAsync`, after updating `output`.

    ```csharp
    // Inspect range IDs across all pages to see which partitions the query reached.
    foreach (ServerSidePartitionedMetrics partition in page.Diagnostics.GetQueryMetrics().PartitionedMetrics)
    {
        Console.WriteLine($"    partition {partition.PartitionKeyRangeId}: {partition.RequestCharge:0.00} RU");
    }
    ```

1. Run the application again. Compare the distinct partition key range IDs across all pages for the price-only query and the category-scoped query.

1. In the Azure portal, open the account and select **Metrics**. Select **Physical Partition Count** with **Maximum** aggregation. Filter **DatabaseName** to `cosmicworks`, **CollectionName** to `product`, and **Region** to one account region. Use the latest metric sample and allow for reporting delay. A value of 1 means both queries run on the same physical partition.

## Clean up resources

When you finish the course, delete the resource group only if you created it and every resource in it can be removed. If your lab provided `ResourceGroup1`, skip this command and delete only the exercise resources you no longer need:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name <your-account-name> --resource-group $resourceGroup --yes
```

The composite index you added in Task 4 stays on the `product` container until you remove it. Adding it preserves query results but can change query and write charges, including baselines in later exercises. Record the policy change before comparing costs in another exercise.

Review your measurements and identify which changes reduced the number of documents retrieved or the request charge.
