---
lab:
  title: Optimize an indexing strategy in C#
  module: Module 12 - Design and Optimize an Indexing Strategy in Azure Cosmos DB
  description: Measure write trimming, require a composite index, index computed properties and spatial data, and verify global secondary index routing, propagation, and write overhead.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Optimize an indexing strategy in C#

In this exercise, you optimize indexing on a CosmicWorks product catalog. You measure index-maintenance cost, add composite and computed-property indexes, query a spatial index, and verify a global secondary index (GSI).

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

## Set up your Azure Cosmos DB resources

This exercise uses a separate Azure Cosmos DB account with continuous backup, which global secondary indexes require. Delete this account at the end of the exercise.

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

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    .\setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab12 -LabProfile indexing
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab12a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, continuous backup at the `Continuous7Days` tier, with key-based authentication disabled |
| `cosmicworks` database | Holds the containers this exercise uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks database-v4 products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 database-v4 category and tag documents |
| `indexingLab` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, left empty for the lab fixtures |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Task 6 adds a fourth container for the GSI. Throughput and storage charges apply.

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#9888; Use the new account created by the setup script. Existing indexes can affect the baseline measurements.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

1. Set variables for the account name and endpoint, then verify the resources:

    ```powershell
    $accountName = "<your-account-name>"
    $env:COSMOS_ENDPOINT = "<your-account-endpoint>"
    .\verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile indexing
    ```

## Task 1: Create the application and write probe

1. Keep the **same PowerShell terminal** open in **Allfiles\Labs\Shared** so `$resourceGroup`, `$accountName`, `$location`, and `$env:COSMOS_ENDPOINT` remain available. Create your own console application:

    ```powershell
    New-Item -ItemType Directory -Path indexing-lab -Force
    Set-Location .\indexing-lab
    dotnet new console --framework net10.0
    dotnet add package Microsoft.Azure.Cosmos --version 3.49.0
    dotnet add package Azure.Identity --version 1.13.2
    dotnet add package Newtonsoft.Json --version 13.0.3
    ```

1. Replace **Program.cs** with the following code. Keep the declarations and helpers above the `// TASK CODE` marker for later tasks.

    ```csharp
    using System.Globalization;
    using System.Text;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;
    using Newtonsoft.Json;
    using Newtonsoft.Json.Linq;

    const string categoryId = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F";
    const string sku = "BK-R93R-44";
    const string productId = "FD48A179-6CF5-45F2-8605-9DA19B9D4409";
    string endpoint = Environment.GetEnvironmentVariable("COSMOS_ENDPOINT")
        ?? throw new InvalidOperationException("Set COSMOS_ENDPOINT in this terminal.");
    // Use the identity from az login.
    using CosmosClient client = new(endpoint, new AzureCliCredential());
    Database database = client.GetDatabase("cosmicworks");
    Container product = database.GetContainer("product");
    Container sandbox = database.GetContainer("indexingLab");
    Container meta = database.GetContainer("productMeta");

    static async Task<(List<T> Items, double RU)> QueryAsync<T>(
        Container container, QueryDefinition query, PartitionKey? partitionKey = null,
        CancellationToken cancellationToken = default)
    {
        List<T> items = [];
        double charge = 0;
        using FeedIterator<T> iterator = container.GetItemQueryIterator<T>(query,
            requestOptions: new QueryRequestOptions
            {
                // Supplying a key scopes the request to one logical partition.
                PartitionKey = partitionKey,
                MaxConcurrency = 0
            });
        while (iterator.HasMoreResults)
        {
            FeedResponse<T> page = await iterator.ReadNextAsync(cancellationToken);
            // Include every page, not just the first, in the query's total charge.
            charge += page.RequestCharge;
            items.AddRange(page);
        }
        return (items, charge);
    }

    static JObject Clean(JObject document)
    {
        // Keep all business fields, but don't send server-managed metadata back.
        JObject body = (JObject)document.DeepClone();
        foreach (JProperty property in body.Properties()
            .Where(property => property.Name.StartsWith('_')).ToArray())
            property.Remove();
        return body;
    }

    static async Task<double> MeanReplaceAsync(
        Container container, JObject document, string partitionValue)
    {
        JObject body = Clean(document);
        string id = body.Value<string>("id")
            ?? throw new InvalidOperationException("Item id is missing.");
        // ETags detect an outside edit that would invalidate this measurement.
        string etag = document.Value<string>("_etag")
            ?? throw new InvalidOperationException("Read the item before measuring.");
        double total = 0;
        // Average three replacements of the identical body, excluding setup writes.
        for (int sample = 0; sample < 3; sample++)
        {
            ItemResponse<JObject> written = await container.ReplaceItemAsync(
                body, id, new PartitionKey(partitionValue),
                new ItemRequestOptions { IfMatchEtag = etag });
            total += written.RequestCharge;
            if (!JToken.DeepEquals(body, Clean(written.Resource)))
                throw new InvalidOperationException("The business body changed.");
            etag = written.ETag;
        }
        return total / 3;
    }

    static async Task<bool> IndexReadyAsync(Container container)
    {
        // A policy update can finish before its new indexes are ready for queries.
        ContainerResponse response = await container.ReadContainerAsync(
            new ContainerRequestOptions { PopulateQuotaInfo = true });
        string? header = response.Headers[
            "x-ms-documentdb-collection-index-transformation-progress"];
        if (!int.TryParse(header, NumberStyles.Integer, CultureInfo.InvariantCulture,
                out int progress) || progress is < 0 or > 100)
            throw new InvalidOperationException("Missing index-transformation percentage.");
        Console.WriteLine($"{container.Id} index transformation: {progress}%");
        return progress == 100;
    }

    // TASK CODE
    var products = await QueryAsync<JToken>(product,
        new QueryDefinition("SELECT VALUE COUNT(1) FROM c"));
    var metadata = await QueryAsync<JToken>(meta,
        new QueryDefinition("SELECT VALUE COUNT(1) FROM c"));
    var tags = await QueryAsync<JObject>(meta,
        new QueryDefinition("SELECT c.id,c.name FROM c WHERE c.type='tag'"),
        new PartitionKey("tag"));
    if (products.Items.Single().Value<int>() != 295 ||
        metadata.Items.Single().Value<int>() != 237 || tags.Items.Count != 200 ||
        tags.Items.Select(tag => tag.Value<string>("id")).Distinct().Count() != 200)
        throw new InvalidOperationException("Expected 295 products and 237 metadata items, including 200 tags.");

    ItemResponse<JObject> source = await product.ReadItemAsync<JObject>(
        productId, new PartitionKey(categoryId));
    if (source.Resource.Value<string>("sku") != sku)
        throw new InvalidOperationException("Unexpected source SKU.");
    // Expand tags only in the sandbox to expose unused index-maintenance work.
    JObject probe = Clean(source.Resource);
    probe["id"] = "indexing-write-probe";
    probe["labPurpose"] = "write-probe";
    // Stable ordering keeps the before/after replacement bodies identical.
    probe["tags"] = new JArray(tags.Items
        .OrderBy(tag => tag.Value<string>("id"), StringComparer.Ordinal));
    // Prepare the probe first; its upsert charge isn't part of the replace average.
    ItemResponse<JObject> saved = await sandbox.UpsertItemAsync(
        probe, new PartitionKey(categoryId));
    Console.WriteLine($"Probe: {tags.Items.Count} tags, " +
        $"{Encoding.UTF8.GetByteCount(probe.ToString(Formatting.None))} UTF-8 bytes.");
    Console.WriteLine($"Probe replace, average of 3: " +
        $"{await MeanReplaceAsync(sandbox, saved.Resource, categoryId):F2} RU");

    var lookup = await QueryAsync<JObject>(sandbox,
        new QueryDefinition("SELECT c.id,c.sku,c.name,c.price FROM c " +
            "WHERE c.id='indexing-write-probe' AND c.sku=@sku")
            .WithParameter("@sku", sku), new PartitionKey(categoryId));
    if (lookup.Items.Count != 1)
        throw new InvalidOperationException("Expected the indexed probe lookup to return one item.");
    Console.WriteLine($"SKU lookup: {lookup.RU:F2} RU; " +
        lookup.Items.Single().ToString(Formatting.None));
    ```

1. Build and run:

    ```powershell
    dotnet build
    dotnet run --no-build
    ```

    Record the average probe replacement charge as **Before trimming** and retain the lookup result.
    Only the sandbox copy has expanded tags; all 295 original products, including their original tags, remain unchanged.

## Task 2: Create an opt-out indexing policy

1. Create **index-policy.json** in your **indexing-lab** folder with this JSON object:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" }
      ],
      "excludedPaths": [
        { "path": "/tags/*" },
        { "path": "/description/?" },
        { "path": "/\"_etag\"/?" }
      ]
    }
    ```

    Root `/*` inclusion retains default range indexing; the exclusions remove unused tag and description paths without removing the SKU index.

1. Apply your policy **only to indexingLab**, then run **Program.cs unchanged**:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name indexingLab --idx "@index-policy.json"
    dotnet run
    ```

    Compare the new average with **Before trimming**: the 200-tag probe should cost fewer write RUs, while the same indexed lookup still returns the same item.

## Task 3: Create a composite index

1. In **Program.cs**, **replace everything from `// TASK CODE` through the end of the file** with this block; retain all declarations and helpers above the marker:

    ```csharp
    // TASK CODE
    if (!await IndexReadyAsync(product))
        return;
    // Both ORDER BY paths must match a composite index, in this sequence.
    var sorted = await QueryAsync<JObject>(product,
        new QueryDefinition("SELECT c.id,c.sku,c.price FROM c " +
            "WHERE c.categoryId=@categoryId ORDER BY c.categoryId,c.price DESC")
            .WithParameter("@categoryId", categoryId));
    if (sorted.Items.Count != 43 ||
        !sorted.Items.Select(item => item.Value<decimal>("price"))
            .SequenceEqual(sorted.Items.Select(item => item.Value<decimal>("price"))
                .OrderDescending()))
        throw new InvalidOperationException("Expected 43 products in descending price order.");
    Console.WriteLine($"Sorted products: {sorted.Items.Count}; {sorted.RU:F2} RU");
    foreach (JObject item in sorted.Items.Take(3))
        Console.WriteLine(item.ToString(Formatting.None));
    ```

1. Run **before** adding the index:

    ```powershell
    dotnet run
    ```

    Expect HTTP **400** stating that the two-property `ORDER BY` needs a composite index.

1. Create **product-policy.json** with root indexing and a matching composite index:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" }
      ],
      "excludedPaths": [
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

1. Apply it and rerun the **same program**:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name product --idx "@product-policy.json"
    dotnet run
    ```

    Repeat `dotnet run` until transformation reaches **100%**; while incomplete, the program prints only progress and exits before querying.

    Confirm **43** products in descending price order. The matching composite index lets the catalog run this category-and-price sort without changing the query.

## Task 4: Create and index a computed property

1. In the **same terminal**, construct the computed-property object and complete ARM container definition:

    ```powershell
    $subscriptionId = (az account show --query id --output tsv)
    $containerId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$accountName/sqlDatabases/cosmicworks/containers/product"
    # Derive the category without adding a stored product field.
    $computedProperty = @{
        name = 'cp_primaryCategory'
        query = "SELECT VALUE SUBSTRING(c.categoryName, 0, INDEX_OF(c.categoryName, ',')) FROM c"
    }
    $containerDefinition = @{
        location = $location
        properties = @{
            resource = @{
                id = 'product'
                partitionKey = @{ paths = @('/categoryId'); kind = 'Hash'; version = 2 }
                # Retain the composite index when replacing the container definition.
                indexingPolicy = (Get-Content -Raw .\product-policy.json | ConvertFrom-Json)
                computedProperties = @($computedProperty)
            }
        }
    }
    $containerDefinition | ConvertTo-Json -Depth 30 |
        Set-Content .\product-definition.json -Encoding utf8
    az rest --method PUT `
        --uri "https://management.azure.com${containerId}?api-version=2025-04-15" `
        --body "@product-definition.json"
    az resource wait --ids $containerId --api-version 2025-04-15 `
        --custom "properties.resource.computedProperties[0].name == 'cp_primaryCategory'" `
        --interval 5 --timeout 900
    ```

1. **Replace everything from `// TASK CODE` to EOF** with:

    ```csharp
    // TASK CODE
    if (!await IndexReadyAsync(product))
        return;
    // Select the derived value explicitly; SELECT * omits computed properties.
    // ORDER BY also needs the explicit /cp_primaryCategory/? index path.
    var computed = await QueryAsync<JObject>(product,
        new QueryDefinition("SELECT c.sku,c.cp_primaryCategory FROM c ORDER BY c.cp_primaryCategory"));
    string[] groups = computed.Items
        .Select(item => item.Value<string>("cp_primaryCategory") ?? "")
        .Distinct().Order(StringComparer.Ordinal).ToArray();
    if (computed.Items.Count != 295 ||
        !groups.SequenceEqual(["Accessories", "Bikes", "Clothing", "Components"]))
        throw new InvalidOperationException("Expected 295 items and four nonempty primary categories.");
    Console.WriteLine($"Computed categories: {computed.Items.Count}; {computed.RU:F2} RU");
    Console.WriteLine(string.Join(", ", groups));
    foreach (JObject item in computed.Items.Take(3))
        Console.WriteLine(item.ToString(Formatting.None));
    // A point read confirms that the computed value wasn't stored in the item.
    var raw = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
    if (raw.Resource.Property("cp_primaryCategory") is not null)
        throw new InvalidOperationException("The computed property must not be persisted in the item.");
    ```

1. Run:

    ```powershell
    dotnet run
    ```

    If index transformation is incomplete, wait and run the program again. Expect HTTP **400** for the missing `ORDER BY` index. The root wildcard doesn't index computed properties.

1. Edit **product-policy.json** to add the explicit computed path, retaining the composite index:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" },
        { "path": "/cp_primaryCategory/?" }
      ],
      "excludedPaths": [
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

1. Update your ARM object from that file, serialize it, and apply it:

    ```powershell
    # Update only the policy, preserving the computed definition in the ARM object.
    $containerDefinition.properties.resource.indexingPolicy =
        (Get-Content -Raw .\product-policy.json | ConvertFrom-Json)
    $containerDefinition | ConvertTo-Json -Depth 30 |
        Set-Content .\product-definition.json -Encoding utf8
    az rest --method PUT `
        --uri "https://management.azure.com${containerId}?api-version=2025-04-15" `
        --body "@product-definition.json"
    az resource wait --ids $containerId --api-version 2025-04-15 `
        --custom "properties.resource.indexingPolicy.includedPaths[?path=='/cp_primaryCategory/?']" `
        --interval 5 --timeout 900
    dotnet run
    ```

    Repeat `dotnet run` until the SDK reports **100%** and the same query returns **295 items** in **Accessories, Bikes, Clothing, Components**.

## Task 5: Create GeoJSON objects and a spatial index

1. Edit your sandbox **index-policy.json** to include a Point spatial index while retaining the exclusions:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        { "path": "/*" }
      ],
      "excludedPaths": [
        { "path": "/tags/*" },
        { "path": "/description/?" },
        { "path": "/\"_etag\"/?" }
      ],
      "spatialIndexes": [
        { "path": "/location/*", "types": ["Point"] }
      ]
    }
    ```

1. Apply your sandbox policy:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name indexingLab --idx "@index-policy.json"
    ```

1. **Replace everything from `// TASK CODE` to EOF** with the following code to create three sandbox copies with sample GeoJSON locations:

    ```csharp
    // TASK CODE
    if (!await IndexReadyAsync(sandbox))
        return;
    var source = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
    JObject seattle = Clean(source.Resource);
    seattle["id"] = "spatial-seattle";
    seattle["labPurpose"] = "spatial";
    seattle["fulfillmentCity"] = "Seattle";
    // GeoJSON Point coordinates are longitude first, then latitude.
    seattle["location"] = new JObject
    {
        ["type"] = "Point",
        ["coordinates"] = new JArray(-122.33, 47.60)
    };
    JObject bellevue = Clean(source.Resource);
    bellevue["id"] = "spatial-bellevue";
    bellevue["labPurpose"] = "spatial";
    bellevue["fulfillmentCity"] = "Bellevue";
    bellevue["location"] = new JObject
    {
        ["type"] = "Point",
        ["coordinates"] = new JArray(-122.2015, 47.6101)
    };
    JObject boston = Clean(source.Resource);
    boston["id"] = "spatial-boston";
    boston["labPurpose"] = "spatial";
    boston["fulfillmentCity"] = "Boston";
    boston["location"] = new JObject
    {
        ["type"] = "Point",
        ["coordinates"] = new JArray(-71.06, 42.36)
    };
    // Store these test locations in the sandbox, not the original catalog.
    foreach (JObject copy in new[] { seattle, bellevue, boston })
        await sandbox.UpsertItemAsync(copy, new PartitionKey(categoryId));
    // ST_DISTANCE uses meters: 25,000 meters is a 25-km search radius.
    var nearby = await QueryAsync<JObject>(sandbox,
        new QueryDefinition("""
            SELECT c.id,c.fulfillmentCity FROM c WHERE c.labPurpose='spatial'
            AND ST_DISTANCE(c.location,{"type":"Point","coordinates":[-122.33,47.60]})<25000
            """), new PartitionKey(categoryId));
    string[] ids = nearby.Items.Select(item => item.Value<string>("id")!)
        .Order(StringComparer.Ordinal).ToArray();
    if (!ids.SequenceEqual(["spatial-bellevue", "spatial-seattle"]))
        throw new InvalidOperationException("Expected only Seattle and Bellevue within 25 km.");
    Console.WriteLine($"Nearby fulfillment cities: {nearby.Items.Count}; {nearby.RU:F2} RU");
    foreach (JObject item in nearby.Items)
        Console.WriteLine(item.ToString(Formatting.None));
    ```

1. Run, repeating until index transformation reaches **100%**:

    ```powershell
    dotnet run
    ```

    The query should return Seattle and Bellevue, but not Boston, within **25,000 meters**.

## Task 6: Create a GSI and test automatic propagation

1. **Replace everything from `// TASK CODE` to EOF** with this source-write measurement:

    ```csharp
    // TASK CODE
    // Capture the source-write baseline before the GSI adds synchronization work.
    var source = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
    Console.WriteLine($"Before GSI, source replace average of 3: " +
        $"{await MeanReplaceAsync(product, source.Resource, categoryId):F2} RU");
    ```

1. Run the program **before creating the GSI**. Write down the RU number next to **Before GSI, source replace average of 3**:

    ```powershell
    dotnet run
    ```

    You'll type this number later when the program asks for it. Don't change the product or its indexing policy between these runs.

1. Create **capabilities.json** with this account-update object:

    ```json
    {
      "properties": {
        "enableMaterializedViews": true
      }
    }
    ```

1. Enable GSI support and wait for the account update:

    ```powershell
    $accountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$accountName"
    az rest --method PATCH `
        --uri "https://management.azure.com${accountId}?api-version=2022-11-15-preview" `
        --body "@capabilities.json"
    if ($LASTEXITCODE -ne 0) { throw "The feature update failed. Check the error above." }
    az resource wait --ids $accountId --api-version 2022-11-15-preview `
        --custom "properties.enableMaterializedViews && properties.provisioningState == 'Succeeded'" `
        --interval 10 --timeout 900
    if ($LASTEXITCODE -ne 0) { throw "The feature check failed. Stop here." }
    ```

1. Construct your GSI definition object and write **gsi-definition.json** using the actual `$location`:

    ```powershell
    $gsiDefinition = @{
        location = $location
        properties = @{
            resource = @{
                id = 'productBySku'
                # The copy is partitioned by SKU; the source stays on /categoryId.
                partitionKey = @{ paths = @('/sku'); kind = 'Hash'; version = 2 }
                materializedViewDefinition = @{
                    sourceCollectionId = 'product'
                    # Project id so its source value is available as _id in the GSI.
                    definition = 'SELECT c.id,c.sku,c.name,c.price,c.categoryId FROM c'
                }
            }
            options = @{ autoscaleSettings = @{ maxThroughput = 1000 } }
        }
    }
    $gsiDefinition | ConvertTo-Json -Depth 30 |
        Set-Content .\gsi-definition.json -Encoding utf8
    $gsiId = "${accountId}/sqlDatabases/cosmicworks/containers/productBySku"
    az rest --method PUT `
        --uri "https://management.azure.com${gsiId}?api-version=2022-11-15-preview" `
        --body "@gsi-definition.json"
    if ($LASTEXITCODE -ne 0) { throw "Couldn't create productBySku. Check the error above." }
    az resource wait --exists --ids $gsiId --api-version 2022-11-15-preview `
        --interval 5 --timeout 900
    if ($LASTEXITCODE -ne 0) { throw "Could not confirm productBySku exists. Stop here." }
    $createdIndex = az cosmosdb sql container show `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name productBySku --query "resource.id" --output tsv
    if ($LASTEXITCODE -ne 0 -or $createdIndex -cne "productBySku") {
        throw "Couldn't find productBySku in this account. Stop here."
    }
    Write-Host "Created productBySku."
    ```

    Confirm **Created productBySku.** appears before continuing.

1. In **Program.cs**, insert this **generic polling helper immediately before `// TASK CODE`**, after the existing helpers:

    ```csharp
    static async Task WaitAsync(string stage, Func<CancellationToken, Task<bool>> ready)
    {
        // GSI propagation is asynchronous; bound each data-readiness wait.
        using CancellationTokenSource timeout = new(TimeSpan.FromMinutes(15));
        try
        {
            while (true)
            {
                if (await ready(timeout.Token))
                    return;
                await Task.Delay(TimeSpan.FromSeconds(5), timeout.Token);
            }
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            throw new TimeoutException($"Timed out after 15 minutes waiting for {stage}.");
        }
    }
    ```

1. **Replace everything from `// TASK CODE` to EOF** with this block, keeping the polling helper above it. The code compares request charges and checks that a source-only update reaches the GSI.

    ```csharp
    // TASK CODE
    Container productBySku = database.GetContainer("productBySku");
    // SKU isn't the source partition key, so this lookup isn't partition-scoped.
    QueryDefinition sourceQuery = new QueryDefinition(
        "SELECT c.id AS sourceId,c.sku,c.name,c.price,c.categoryId FROM c WHERE c.sku=@sku")
        .WithParameter("@sku", sku);
    // The GSI generates id; _id preserves the source id for result comparison.
    QueryDefinition gsiQuery = new QueryDefinition(
        "SELECT c._id AS sourceId,c.sku,c.name,c.price,c.categoryId FROM c WHERE c.sku=@sku")
        .WithParameter("@sku", sku);
    var sourceLookup = await QueryAsync<JObject>(product, sourceQuery);
    if (sourceLookup.Items.Count != 1 ||
        sourceLookup.Items[0].Value<string>("sourceId") != productId)
        throw new InvalidOperationException("Expected one source SKU match.");
    (List<JObject> Items, double RU)? gsiLookup = null;
    int lastCopied = -1;
    Console.WriteLine("Waiting for the GSI copy...");
    // Wait for the initial 295-product copy.
    await WaitAsync("productBySku", async token =>
    {
        var count = await QueryAsync<JToken>(productBySku,
            new QueryDefinition("SELECT VALUE COUNT(1) FROM c"),
            cancellationToken: token);
        int copied = count.Items.Single().Value<int>();
        if (copied != lastCopied)
        {
            Console.WriteLine($"Products copied: {copied}/295");
            lastCopied = copied;
        }
        if (copied != 295)
            return false;
        // The explicit SKU key routes this request to one GSI logical partition.
        var routed = await QueryAsync<JObject>(productBySku, gsiQuery,
            new PartitionKey(sku), token);
        if (routed.Items.Count != 1 ||
            !JToken.DeepEquals(sourceLookup.Items[0], routed.Items[0]))
            return false;
        gsiLookup = routed;
        return true;
    });
    Console.WriteLine($"Source cross-partition SKU lookup: {sourceLookup.RU:F2} RU");
    Console.WriteLine($"GSI /sku-targeted lookup: {gsiLookup!.Value.RU:F2} RU");
    Console.WriteLine(gsiLookup.Value.Items.Single().ToString(Formatting.None));

    Console.Write("Before GSI source replace charge (number only, with a decimal point): ");
    if (!double.TryParse(Console.ReadLine(), NumberStyles.Float,
            CultureInfo.InvariantCulture, out double beforeGsi) ||
        !double.IsFinite(beforeGsi) || beforeGsi <= 0)
        throw new InvalidOperationException("Type the RU number saved at the start of Task 6, without the letters RU.");
    var measured = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
    // Keep the item and policy unchanged to isolate the GSI's added write charge.
    double afterGsi = await MeanReplaceAsync(product, measured.Resource, categoryId);
    Console.WriteLine($"Source replace average: before {beforeGsi:F2} RU; " +
        $"after {afterGsi:F2} RU; added write charge {afterGsi - beforeGsi:F2} RU.");

    var source = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
    JObject original = Clean(source.Resource);
    JObject changed = (JObject)original.DeepClone();
    // Write only to the source; Azure Cosmos DB updates the read-only GSI.
    changed["price"] = original.Value<decimal>("price") + 1.00m;
    JObject originalProjection = sourceLookup.Items.Single();
    JObject changedProjection = (JObject)originalProjection.DeepClone();
    changedProjection["price"] = changed["price"]!.DeepClone();
    try
    {
        Console.WriteLine($"Changing only source price: {original["price"]} -> {changed["price"]}");
        await product.ReplaceItemAsync(changed, productId, new PartitionKey(categoryId),
            new ItemRequestOptions { IfMatchEtag = source.ETag });
        await WaitAsync("temporary price propagation", async token =>
        {
            var result = await QueryAsync<JObject>(productBySku, gsiQuery,
                new PartitionKey(sku), token);
            return result.Items.Count == 1 &&
                JToken.DeepEquals(result.Items[0], changedProjection);
        });
        Console.WriteLine("The GSI received the new source price and matching _id automatically.");
    }
    finally
    {
        // Restore the original data even if the propagation check fails.
        Console.WriteLine($"Restoring original source price {original["price"]}...");
        var current = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
        JObject currentBody = Clean(current.Resource);
        // Don't overwrite an unrelated concurrent edit while undoing our price change.
        if (!JToken.DeepEquals(currentBody, original) && !JToken.DeepEquals(currentBody, changed))
            throw new InvalidOperationException("Unexpected concurrent source change; refusing to overwrite it.");
        if (!JToken.DeepEquals(currentBody, original))
            await product.ReplaceItemAsync(original, productId, new PartitionKey(categoryId),
                new ItemRequestOptions { IfMatchEtag = current.ETag });
        var restored = await product.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
        if (!JToken.DeepEquals(Clean(restored.Resource), original))
            throw new InvalidOperationException("Original source body was not restored.");
        // Verify that the restoration reaches the GSI as well as the source.
        await WaitAsync("restored price propagation", async token =>
        {
            var result = await QueryAsync<JObject>(productBySku, gsiQuery,
                new PartitionKey(sku), token);
            return result.Items.Count == 1 &&
                JToken.DeepEquals(result.Items[0], originalProjection);
        });
        Console.WriteLine("Original source body restored; the GSI also shows the original price.");
    }
    ```

1. Run the program. When it asks for the charge, type the **number you saved at the start of Task 6**, without `RU`, and press **Enter**:

    ```powershell
    dotnet run
    ```

    The program prints the initial copy progress. Each copy or propagation check has a **15-minute timeout**.

    Compare the source and GSI lookup charges and the before-and-after source replacement charges. Lookup charges might be equal for this small catalog. The `sourceId` projections use `id` from the source and `_id` from the GSI.

    Confirm that both the temporary price change and the restored price appear in the GSI. The program writes only to the source container.

## Clean up

Delete **only the Cosmos DB account created for this lab**, preserving the supplied/shared resource group:

```powershell
az cosmosdb delete --resource-group $resourceGroup --name $accountName --yes
```

## References

- [Manage indexing policies and transformation progress](https://learn.microsoft.com/azure/cosmos-db/how-to-manage-indexing-policy)
- [Computed properties](https://learn.microsoft.com/cosmos-db/query/computed-properties)
- [Spatial indexing](https://learn.microsoft.com/azure/cosmos-db/how-to-geospatial-index-query)
- [Global secondary indexes](https://learn.microsoft.com/azure/cosmos-db/global-secondary-indexes)
