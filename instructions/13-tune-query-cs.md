---
lab:
  title: Tune a high-cost query in C#
  module: Module 13 - Analyze and Tune Query and Operation Performance in Azure Cosmos DB
  description: Baseline three operations against a product catalog, prove a scan with query metrics, rewrite the filter so the index serves it, add a composite index, and compare fan-out with single-partition routing.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you diagnose an expensive query the way the metrics ask you to: measure first, read the evidence, then change one thing at a time. You start by recording a baseline for three operations against a product catalog, then use the server-side query metrics to prove that one of them scans the container, rewrite it so the index serves the filter, add a composite index for a two-property filter, and finish by comparing a query that fans out with the same query scoped to a single partition.

Every task produces a number you can compare against the one before it. Those comparisons are the point of the exercise, so write your numbers down as you go. Request charges depend on your data and query configuration, so treat the sample values in this exercise as illustrations of shape rather than targets to match.

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

> [!NOTE]
> A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

## Task 1: Record a baseline

Three operations stand in for the shapes an application runs: a point read by ID, a query whose filter calls a case-conversion function, and a query filtering on two properties. Measure all three before changing anything.

1. In the terminal, create a project folder and a console application.

    ```powershell
    mkdir query-tuning-lab
    cd query-tuning-lab
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
    string categoryId = "75BF1ACB-168D-469C-9AA3-1FD26BB4EA4C";
    string productId = "BD340F0A-F661-4ED8-B36F-FBA7623605D9";

    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Container product = client.GetDatabase("cosmicworks").GetContainer("product");

    ItemResponse<Product> read = await product.ReadItemAsync<Product>(
        productId, new PartitionKey(categoryId));
    Console.WriteLine($"{"point read",-24}: {read.RequestCharge,8:0.00} RU  ({read.Resource.name})");

    await MeasureAsync(product, "scan on UPPER(name)",
        "SELECT * FROM c WHERE UPPER(c.name) = @name",
        ("@name", "TOURING-3000 BLUE, 62"));

    await MeasureAsync(product, "category and price",
        "SELECT * FROM c WHERE c.categoryId = @categoryId AND c.price > @floor",
        ("@categoryId", categoryId), ("@floor", 1000));

    static async Task MeasureAsync(Container container, string label, string text,
        params (string Name, object Value)[] parameters)
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

        Console.WriteLine($"{label,-24}: {charge,8:0.00} RU for {items} items");
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
    }
    ```

1. Run the application.

    ```powershell
    dotnet run
    ```

    The output reports one charge per operation, and the item counts confirm the queries match the data you expect.

    ```output
    point read              :     1.00 RU  (Touring-3000 Blue, 62)
    scan on UPPER(name)     :    12.86 RU for 1 items
    category and price      :     3.29 RU for 12 items
    ```

The point read is your reference for the same item and consistency level. A point read of a 1 KB item costs 1 request unit (RU) with session, consistent prefix, or eventual consistency. Strong and bounded staleness reads cost twice as much. Record the consistency level and all three charges before continuing.

## Task 2: Prove the scan with query metrics

The second query returns one item. Whether it's expensive depends on how many items the engine had to load to find that item, and only the server-side metrics reveal that count.

1. In **Program.cs**, replace the body of the `while` loop inside `MeasureAsync` with the following code, which reads the query metrics from each page.

    ```csharp
    FeedResponse<Product> page = await iterator.ReadNextAsync();
    charge += page.RequestCharge;
    items += page.Count;

    ServerSideMetrics metrics = page.Diagnostics.GetQueryMetrics().CumulativeMetrics;
    retrieved += metrics.RetrievedDocumentCount;
    output += metrics.OutputDocumentCount;
    ```

1. Declare the two counters beside the existing ones, above the `FeedIterator<Product>` line.

    ```csharp
    long retrieved = 0;
    long output = 0;
    ```

1. Replace the `Console.WriteLine` at the end of `MeasureAsync` with a line that reports both counts.

    ```csharp
    Console.WriteLine(
        $"{label,-24}: {charge,8:0.00} RU  retrieved {retrieved,4}  output {output,4}");
    ```

1. Run the application again.

    ```powershell
    dotnet run
    ```

The two queries now separate clearly.

```output
scan on UPPER(name)     :    12.86 RU  retrieved  295  output    1
category and price      :     3.29 RU  retrieved   12  output   12
```

The scan loaded all 295 products in the container to return one. The second query loaded exactly what it returned. Those queries match the two categories from earlier in this module, and they call for different fixes.

## Task 3: Rewrite the filter so the index serves it

`UPPER` isn't served from the index, so the engine has no choice but to load every document and evaluate the function against each one. For this lookup, you know the exact stored product name, so you can compare it directly without converting its casing.

1. In your application, change the scan query's filter to compare the property directly and pass the value in its stored casing.

    ```csharp
    await MeasureAsync(product, "direct name match",
        "SELECT * FROM c WHERE c.name = @name",
        ("@name", "Touring-3000 Blue, 62"));
    ```

1. Run the application again and compare the retrieved count with the value you recorded in Task 2.

    ```output
    direct name match       :     2.87 RU  retrieved    1  output    1
    ```

The retrieved count drops from 295 to 1. The query still returns the same product, and the request charge falls with the work. Nothing about the indexing policy changed; the default policy already indexed `/name/?`, and the original query wrote a filter the index couldn't be asked about.

## Task 4: Add a composite index for the two-property filter

The category and price query is already index-served, so there's no scan left to remove. A composite index can still help, because a query combining an equality filter with a range filter can be answered from a single composite index rather than by intersecting two range indexes.

1. Turn on index metrics for that query and look at what the engine reports.

    Add a request options object inside `MeasureAsync` and pass it to the iterator.

    ```csharp
    QueryRequestOptions options = new() { PopulateIndexMetrics = true };
    FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(query, requestOptions: options);
    ```

    Then print the metrics from the first page by adding this line inside the `while` loop.

    ```csharp
    Console.WriteLine(page.IndexMetrics);
    ```

1. Run the application and read the index utilization section. Record which paths appear as utilized and whether any composite index appears under the potential section. Your output resembles the following example, though the exact recommendations depend on how the engine evaluates your query against your data.

    ```output
    Index Utilization Information
      Utilized Single Indexes
        Index Spec: /categoryId/?
        Index Impact Score: High
        ---
        Index Spec: /price/?
        Index Impact Score: High
        ---
      Potential Single Indexes
      Utilized Composite Indexes
      Potential Composite Indexes
        Index Spec: /categoryId ASC, /price ASC
        Index Impact Score: High
        ---
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

1. In **Data Explorer**, open the `product` container's **Settings** and check the index transformation progress. Wait until the transformation completes, then run the application again and compare the request charge and index utilization against the baseline. An elapsed minute alone doesn't confirm that the new index is ready.

Index transformation runs in the background and doesn't affect read or write availability, so the container keeps serving queries while it completes. At 295 items, the transformation finishes almost immediately.

## Task 5: Compare fan-out with single-partition routing

The `product` container is partitioned on `/categoryId`. Every query so far that filtered on `categoryId` routed to one partition. This task runs the same price filter with and without that routing.

1. Add a query that filters only on price, leaving the partition key out entirely, and keep the scoped version alongside it.

    ```csharp
    await MeasureAsync(product, "price only (fan-out)",
        "SELECT * FROM c WHERE c.price > @floor",
        ("@floor", 1000));

    await MeasureAsync(product, "price within category",
        "SELECT * FROM c WHERE c.categoryId = @categoryId AND c.price > @floor",
        ("@categoryId", categoryId), ("@floor", 1000));
    ```

1. Run the application and compare the two lines.

    ```output
    price only (fan-out)    :    10.44 RU  retrieved   86  output   86
    price within category   :     3.29 RU  retrieved   12  output   12
    ```

Both queries are fully index-served: retrieved equals output in each case. If the container has one physical partition, the unscoped query costs more because it returns 86 products across every category rather than the 12 in one category, not because it visited more partitions. A fresh core container with this data and throughput usually has one physical partition, but 295 items alone don't prove its layout. Confirm the partition count below before interpreting the difference. If the container has multiple physical partitions, fan-out can also contribute to the unscoped query's cost.

With one physical partition, that null result is worth understanding rather than skipping. The routing behavior is real, but scoping can't reduce the physical partition count below one. In a container with several physical partitions, the unscoped query checks every partition's index and merges the results, while the scoped query checks one. Documentation puts the point where that difference becomes significant at roughly 30,000 provisioned RU/s or about 100 GB of stored data.

1. Confirm the partition count for yourself by printing the per-partition breakdown. Add this code inside the `while` loop in `MeasureAsync`.

    ```csharp
    foreach (ServerSidePartitionedMetrics partition in page.Diagnostics.GetQueryMetrics().PartitionedMetrics)
    {
        Console.WriteLine($"    partition {partition.PartitionKeyRangeId}: {partition.RequestCharge:0.00} RU");
    }
    ```

1. Run the application once more. Compare distinct partition key range IDs across every page of the unscoped query. These IDs identify the partitions the query reaches, not whether the container ever split in the past.

1. To check the container's physical partition count, open the account in the Azure portal and select **Metrics**. Select **Physical Partition Count** with **Maximum** aggregation. Filter **DatabaseName** to `cosmicworks`, **CollectionName** to `product`, and **Region** to one account region. Use the latest metric sample and allow for reporting delay. A count of one confirms that there is no cross-physical-partition fan-out to remove for that sample.

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

Look back at the numbers you recorded. The largest single improvement came from deleting one function call from a `WHERE` clause, and the metrics named that function before you changed anything. That sequence, measure and then read the evidence, is what separates tuning from guessing.
