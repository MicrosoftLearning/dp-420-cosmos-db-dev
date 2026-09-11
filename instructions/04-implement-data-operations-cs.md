---
lab:
  title: Implement Data Operations in C#
  module: Module 4 - Implement Azure Cosmos DB Operations with the SDK
  description: Perform point reads, writes, a conditional patch, an ETag-guarded replace, item time to live, a transactional batch, and a bulk load, comparing request-unit costs.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Implement Data Operations in C#

In this exercise, you build a small data layer against an Azure Cosmos DB for NoSQL container and exercise every operation from this module. You read an item with a point read and compare its cost with the cost of an equivalent query. You then run the full set of write operations. You apply a conditional patch and protect a replace operation with an ETag. You set a time to live (TTL) value to expire an item. You commit a transactional batch. You finish with a bulk load. Throughout, you print the request charge so you can see what each choice costs.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

## Set up your Azure Cosmos DB resources

The core exercises reuse an account prepared with the `core` profile, not the two-item account from the first portal exercise. Before skipping setup, open **Allfiles/Labs/Shared** in PowerShell, sign in with `az login`, and set `$resourceGroup`, `$location`, and `$accountName` to your recorded values. Run `./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile core` and continue only when it succeeds. In Data Explorer, confirm 295 items in `cosmicworks/product` and 237 in `cosmicworks/productMeta` with `SELECT VALUE COUNT(1) FROM c`.

If you have no verified core account, follow the setup steps below. To add missing resources to an existing lab account, pass its explicit `-AccountName` to setup rather than using a different module's name prefix. Reseeding restores canonical items but doesn't remove extra items or reset container policies. Resolve mismatches before continuing; don't reset a shared account automatically.

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

1. Set variables for the resource group (If a resource group was provided by your lab environment, use that name) and region you want to use. Change either value if you prefer a different resource group name or region.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab04 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab04a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint throughout this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources, with throughput measured in request units per second (RU/s):

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds every container this learning path uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, seeded with 295 items |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, seeded with 237 items |
| `leases` container | Partitioned on `/id`, manual throughput of 400 RU/s, empty |
| `operations` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, empty. Tasks 2 through 6 work here |
| `bulkload` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, empty. Task 7 writes to it |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |


Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Set up the project and connect to the container

Task 5 expires an item with time to live (TTL), so enable it on the container now. Replace <your-account-name> with your actual account name:

```azurecli
az cosmosdb sql container update `
    --account-name <your-account-name> `
    --resource-group $resourceGroup `
    --database-name cosmicworks `
    --name operations `
    --ttl -1
```

A value of `-1` expires only the items that set their own `ttl`.

1. Open a terminal and create a new console project:

    ```bash
    dotnet new console -n cosmos-operations-exercise
    cd cosmos-operations-exercise
    ```

1. Add the SDK packages:

    ```bash
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Newtonsoft.Json
    dotnet add package Azure.Identity
    ```

1. Open **Program.cs** and replace its contents with the following code. Set `endpoint` to the account endpoint the setup script printed:

    ```csharp
    using System.Diagnostics;
    using System.Net;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";

    CosmosClient client = new(endpoint, new DefaultAzureCredential());
    Container container = client.GetContainer("cosmicworks", "operations");

    // ---- Each task replaces everything below this line ----

    Console.WriteLine("Container ready.");
    ```

    `GetContainer` builds a client-side reference without calling the service, so it needs no control-plane permission.

1. Add a second file named **Models.cs** with the item types:

    ```csharp
    public record Tag(string id, string name);

    public record Product(
        string id,
        string categoryId,
        string categoryName,
        string sku,
        string name,
        double price,
        Tag[] tags);
    ```

    The `Product` record mirrors the cosmicworks product document: `tags` is an array of objects, each with its own `id` and `name`, not an array of strings.

    Keeping the types in their own file leaves **Program.cs** holding nothing but top-level statements, so you can append to the end of it without worrying about declaration order.

    > &#10071; Each task that follows replaces only the code **below the marker comment**. The lines above it, including your endpoint, stay put for the whole exercise. That way every run does only the work of the task you're on, instead of repeating everything before it.

1. Run the project and confirm the output reads `Container ready.`:

    ```bash
    dotnet run
    ```

---

## Task 2: Compare a point read against a query

Create one item, then read it back two ways and compare the request charge.

1. In **Program.cs**, replace everything below the marker comment with the following code. It creates the saddle item that the rest of this exercise works with:

    ```csharp
    string id = "027D0B9A-F9D9-4C96-8213-C8546C4AAE71";
    string categoryId = "26C74104-40BC-4541-8EF5-9892F7F03D72";
    PartitionKey partitionKey = new(categoryId);

    Product saddle = new(
        id,
        categoryId,
        "Components, Saddles",
        "SE-R581",
        "LL Road Seat/Saddle",
        27.12d,
        new[]
        {
            new Tag("0573D684-9140-4DEE-89AF-4E4A90E65666", "Tag-113"),
            new Tag("6C2F05C8-1E61-4912-BE1A-C67A378429BB", "Tag-5")
        });

    try
    {
        await container.CreateItemAsync(saddle, partitionKey);
        Console.WriteLine("Create:      item created");
    }
    catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.Conflict)
    {
        Console.WriteLine("Create:      item already exists");
    }
    ```

1. Add the point read and print its charge:

    ```csharp
    ItemResponse<Product> readResponse = await container.ReadItemAsync<Product>(id, partitionKey);
    Console.WriteLine($"Point read:  {readResponse.RequestCharge:0.00} RU");
    ```

1. Add an equivalent query that filters on the same two values:

    ```csharp
    QueryDefinition query = new QueryDefinition(
            "SELECT * FROM c WHERE c.id = @id AND c.categoryId = @categoryId")
        .WithParameter("@id", id)
        .WithParameter("@categoryId", categoryId);

    double queryCharge = 0;
    using FeedIterator<Product> iterator = container.GetItemQueryIterator<Product>(
        query,
        requestOptions: new QueryRequestOptions { PartitionKey = partitionKey });

    while (iterator.HasMoreResults)
    {
        FeedResponse<Product> page = await iterator.ReadNextAsync();
        queryCharge += page.RequestCharge;
    }

    Console.WriteLine($"Query:       {queryCharge:0.00} RU");
    ```

1. Run the project and compare the two read charges:

    ```bash
    dotnet run
    ```

    ```output
    Create:      item created
    Point read:  1.00 RU
    Query:       2.92 RU
    ```

A point read costs about 1 request unit (RU). Fetching the same item by query costs two to three times as much, because it goes through the query engine. Use a point read whenever your code already knows the `id` and the partition key.

---

## Task 3: Run the write operations

Replace, upsert, and delete the item, then recreate it for the tasks that follow.

1. In **Program.cs**, replace everything below the marker comment with the following code. It reads the item created in Task 2 and replaces it with a new price:

    ```csharp
    string id = "027D0B9A-F9D9-4C96-8213-C8546C4AAE71";
    string categoryId = "26C74104-40BC-4541-8EF5-9892F7F03D72";
    PartitionKey partitionKey = new(categoryId);

    Product saddle = await container.ReadItemAsync<Product>(id, partitionKey);

    Product updated = saddle with { price = 32.55d };

    ItemResponse<Product> replaced = await container.ReplaceItemAsync(updated, id, partitionKey);
    Console.WriteLine($"Replace:     {replaced.RequestCharge:0.00} RU");
    ```

    `ReplaceItemAsync` takes the `id` as a separate argument, and it fails with 404 if the item no longer exists.

1. Add an upsert that suppresses the response payload:

    ```csharp
    ItemRequestOptions noContent = new() { EnableContentResponseOnWrite = false };

    ItemResponse<Product> upserted = await container.UpsertItemAsync(
        updated with { price = 30.00d }, partitionKey, noContent);

    Console.WriteLine($"Upsert:      {upserted.RequestCharge:0.00} RU (no payload returned)");
    ```

1. Add a delete, then recreate the item so later tasks have something to work with:

    ```csharp
    ItemResponse<Product> deleted = await container.DeleteItemAsync<Product>(id, partitionKey);
    Console.WriteLine($"Delete:      {deleted.RequestCharge:0.00} RU");

    await container.CreateItemAsync(saddle, partitionKey);
    ```

1. Run the project and compare the write charges against the read charges from Task 2:

    ```output
    Replace:     10.67 RU
    Upsert:      10.67 RU (no payload returned)
    Delete:      9.52 RU
    ```

A write costs several times a point read, because the charge covers the document itself plus every index term the container's indexing policy maintains. The replace is the most expensive of the three: it deletes the existing document and inserts the new one, paying the document cost twice, while the delete pays it once. Request charges are deterministic for a given operation over a given dataset, so rerunning the project reproduces these numbers, though your values depend on item size and the container's indexing policy. Suppressing the response payload saves network bandwidth, not request units, which is why the replace and the upsert cost the same.

---

## Task 4: Apply a conditional patch and guard a replace with an ETag

Change one property without rewriting the whole document, and make that change conditional. Patch and replace express a condition differently: a patch uses a filter predicate, and a replace uses an ETag. You use both here.

1. In **Program.cs**, replace everything below the marker comment with the following code. It patches two properties, guarded by a filter predicate that tests the current price:

    ```csharp
    string id = "027D0B9A-F9D9-4C96-8213-C8546C4AAE71";
    string categoryId = "26C74104-40BC-4541-8EF5-9892F7F03D72";
    PartitionKey partitionKey = new(categoryId);

    PatchItemRequestOptions patchOptions = new()
    {
        FilterPredicate = "FROM c WHERE c.price < 100"
    };

    try
    {
        ItemResponse<Product> patched = await container.PatchItemAsync<Product>(
            id: id,
            partitionKey: partitionKey,
            patchOperations: new[]
            {
                PatchOperation.Set("/name", "LL Road Seat/Saddle, Clearance"),
                PatchOperation.Increment("/price", 5.00)
            },
            requestOptions: patchOptions);

        Console.WriteLine($"Patch:       {patched.RequestCharge:0.00} RU");
    }
    catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed)
    {
        Console.WriteLine("Patch:       412 Precondition Failed");
    }
    ```

1. Run the project. The predicate holds, so the patch succeeds and the price is now 32.12. Record its request charge alongside the replace charge from Task 3. Patch doesn't guarantee a lower write charge; its benefits include a smaller request payload and avoiding a preceding read when the changes are already known.

1. Now force the condition to fail. Append the following code to the end of **Program.cs**. It uses a predicate the item no longer satisfies:

    ```csharp
    try
    {
        await container.PatchItemAsync<Product>(
            id: id,
            partitionKey: partitionKey,
            patchOperations: new[] { PatchOperation.Increment("/price", 5.00) },
            requestOptions: new PatchItemRequestOptions
            {
                FilterPredicate = "FROM c WHERE c.price < 30"
            });

        Console.WriteLine("Failed patch: unexpectedly succeeded");
    }
    catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed)
    {
        Console.WriteLine("Failed patch: 412 Precondition Failed, as expected");
    }
    ```

1. Now guard a replace with an ETag instead. Append the following code to the end of **Program.cs**. It reads the item, keeps its ETag, and writes with that ETag attached:

    ```csharp
    ItemResponse<Product> current = await container.ReadItemAsync<Product>(id, partitionKey);
    ItemRequestOptions etagOptions = new() { IfMatchEtag = current.ETag };

    await container.ReplaceItemAsync(
        current.Resource with { price = 45.00d }, id, partitionKey, etagOptions);

    Console.WriteLine("Replace:     succeeded with a current ETag");
    ```

1. Reuse the same, now stale, ETag on a second replace:

    ```csharp
    try
    {
        await container.ReplaceItemAsync(
            current.Resource with { price = 50.00d }, id, partitionKey, etagOptions);

        Console.WriteLine("Stale replace: unexpectedly succeeded");
    }
    catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.PreconditionFailed)
    {
        Console.WriteLine("Stale replace: 412 Precondition Failed, as expected");
    }
    ```

1. Run the project. The first replace succeeds and changes the item's ETag, so the second one fails.

This exercise conditions the patch with a filter predicate and the replace with an ETag. The .NET standalone `PatchItemAsync` method doesn't support `IfMatchEtag`, so don't substitute that option for the patch predicate. A replace supports an ETag precondition, but not a filter predicate. Both conditions demonstrated here reject a conflicting write with 412 Precondition Failed. Re-read the item and decide whether to reapply the change. Patch operations inside a transactional batch have separate request options; don't infer their behavior from the standalone method.

---

## Task 5: Expire an item with time to live

Write a transient item, give it a short lifetime, and watch it disappear.

1. In **Program.cs**, replace everything below the marker comment with the following code. It creates a session item with a 30-second lifetime:

    ```csharp
    string categoryId = "26C74104-40BC-4541-8EF5-9892F7F03D72";
    PartitionKey partitionKey = new(categoryId);

    var session = new
    {
        id = "session-9f21",
        categoryId = categoryId,
        state = "active",
        ttl = 30
    };

    await container.UpsertItemAsync(session, partitionKey);
    Console.WriteLine("Session created with a 30 second TTL.");
    ```

    Using an upsert rather than a create lets you rerun the task without a conflict.

1. Add two reads, one before the lifetime elapses and one after, so you can see the item disappear rather than find it missing:

    ```csharp
    async Task ReadSession(string label)
    {
        try
        {
            await container.ReadItemAsync<dynamic>("session-9f21", partitionKey);
            Console.WriteLine($"{label} session still present");
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            Console.WriteLine($"{label} session expired");
        }
    }

    await Task.Delay(TimeSpan.FromSeconds(10));
    await ReadSession("After 10s:");

    await Task.Delay(TimeSpan.FromSeconds(25));
    await ReadSession("After 35s:");
    ```

    To leave a margin, the second read lands at 35 seconds rather than exactly 30. An expired item stops appearing in results as soon as its lifetime elapses, even though the physical delete happens later, as a background task.

1. Run the project. The first read succeeds and the second returns 404:

    ```output
    Session created with a 30 second TTL.
    After 10s: session still present
    After 35s: session expired
    ```

A container TTL of `-1` turns on expiration without giving anything a default lifetime. Only items that set their own `ttl` expire: the session item did, and the product item from Task 2 didn't.

---

## Task 6: Commit a transactional batch

To see how the failure reports itself, write two related items atomically, then break the same-partition rule on purpose.

1. In **Program.cs**, replace everything below the marker comment with the following code. Both items share the partition key value used throughout this exercise:

    ```csharp
    string categoryId = "26C74104-40BC-4541-8EF5-9892F7F03D72";
    PartitionKey partitionKey = new(categoryId);

    Product mountainSaddle = new(
        "201D0D79-81AD-43D2-AD6E-F09EEE6AC2D7", categoryId,
        "Components, Saddles", "SE-M798", "ML Mountain Seat/Saddle", 39.14d, Array.Empty<Tag>());

    Product touringSaddle = new(
        "3FE1A99E-DE14-4D11-B635-F5D39258A0B9", categoryId,
        "Components, Saddles", "SE-T924", "HL Touring Seat/Saddle", 52.64d, Array.Empty<Tag>());

    TransactionalBatch batch = container.CreateTransactionalBatch(partitionKey)
        .UpsertItem(mountainSaddle)
        .UpsertItem(touringSaddle);

    using TransactionalBatchResponse batchResponse = await batch.ExecuteAsync();

    Console.WriteLine($"Batch:       {batchResponse.StatusCode} ({batchResponse.RequestCharge:0.00} RU)");
    ```

    The batch upserts rather than creates, so rerunning the task doesn't fail on items that already exist.

1. Run the project. The status is `OK`, and both items exist in the container.

1. Now build a batch that mixes partition key values. Append the following code to the end of **Program.cs**:

    ```csharp
    Product llMountainSaddle = new(
        "5996B5E0-6EC7-4CB7-A924-7B5A053AE980", categoryId,
        "Components, Saddles", "SE-M236", "LL Mountain Seat/Saddle", 27.12d, Array.Empty<Tag>());

    Product helmet = new(
        "47ED1C3B-C205-4507-94EE-3B69A744B261", "14A1AD5D-59EA-4B63-A189-67B077783B0E",
        "Accessories, Helmets", "HL-U509", "Sport-100 Helmet, Black", 34.99d, Array.Empty<Tag>());

    TransactionalBatch badBatch = container.CreateTransactionalBatch(partitionKey)
        .CreateItem(llMountainSaddle)
        .CreateItem(helmet);

    using TransactionalBatchResponse badResponse = await badBatch.ExecuteAsync();

    for (int i = 0; i < badResponse.Count; i++)
    {
        Console.WriteLine($"  Operation {i}: {(int)badResponse[i].StatusCode}");
    }
    ```

1. Run the project. The batch fails. One operation reports the real error, and the other reports **424 Failed Dependency**, which means it was rolled back rather than rejected on its own merits. Confirm in the Azure portal's **Data Explorer** that neither item was written.

---

## Task 7: Load items in bulk

Write a few thousand independent items and measure how long the load takes.

This task writes to the `bulkload` container rather than `operations`, so the items you created in earlier tasks stay out of the timing measurement.

1. In **Program.cs**, replace everything below the marker comment with the following code. It uses a second client with bulk execution enabled, because that setting can't be changed after a client is created:

    ```csharp
    CosmosClientOptions bulkOptions = new() { AllowBulkExecution = true };
    using CosmosClient bulkClient = new(endpoint, new DefaultAzureCredential(), bulkOptions);

    Container bulkContainer = bulkClient.GetDatabase("cosmicworks").GetContainer("bulkload");

    List<Product> items = Enumerable.Range(0, 2000)
        .Select(i => new Product(
            id: Guid.NewGuid().ToString(),
            categoryId: $"bulk-category-{i % 20}",
            categoryName: $"Bulk Category {i % 20}",
            sku: $"BL-{i:D5}",
            name: $"Bulk Product {i}",
            price: 10.00d + i % 500,
            tags: Array.Empty<Tag>()))
        .ToList();

    Stopwatch timer = Stopwatch.StartNew();

    List<Product> pending = items;
    int firstPassFailures = 0;

    for (int attempt = 0; attempt < 3; attempt++)
    {
        List<Task<Product?>> tasks = pending
            .Select(async item =>
            {
                try
                {
                    await bulkContainer.CreateItemAsync(item, new PartitionKey(item.categoryId));
                    return (Product?)null;
                }
                catch (CosmosException exception) when (
                    exception.StatusCode == HttpStatusCode.TooManyRequests ||
                    exception.StatusCode == (HttpStatusCode)449)
                {
                    return item;
                }
            })
            .ToList();

        Product?[] outcomes = await Task.WhenAll(tasks);
        pending = outcomes.OfType<Product>().ToList();

        if (attempt == 0)
        {
            firstPassFailures = pending.Count;
        }

        if (pending.Count == 0)
        {
            break;
        }

        await Task.Delay(TimeSpan.FromSeconds(2));
    }

    timer.Stop();

    Console.WriteLine($"Bulk load:   {items.Count - pending.Count} of {items.Count} written in {timer.Elapsed.TotalSeconds:0.0} seconds");
    Console.WriteLine($"Retried:     {firstPassFailures} on the first pass, {pending.Count} still outstanding");
    ```

    `AllowBulkExecution` lets the client group concurrent operations by partition key range and send each group as a single request. The 20 partition key values create logical partitions, not physical partitions. This small container can have only one physical partition. Distributing keys supports parallelism across physical partitions when the container scales out.

    The handler retries only 429 and 449 responses, which indicate retryable rejections. Cancellation, nonretryable errors, and ambiguous outcomes such as timeouts propagate instead of being reported as unwritten items. A timed-out create might already have committed, so resolve its outcome before replaying it. `Task.WhenAll` waits for all tasks; its returned task retains their exceptions even though awaiting it throws one.

1. Run the project and note the elapsed time:

    ```bash
    dotnet run
    ```

    ```output
    Bulk load:   2000 of 2000 written in 16.8 seconds
    Retried:     14 on the first pass, 0 still outstanding
    ```

    This output is an example; elapsed time and retry counts vary. The SDK might handle all throttling without surfacing any first-pass failures. If retryable rejections remain, the next pass retries those items, but success isn't guaranteed. Check the final outstanding count. Restarting the whole load creates fresh `Guid` values and can write 2,000 more items instead of finishing the first 2,000.

Bulk mode doesn't make each write cheaper. Every item costs the same RU charge it would cost on its own. What changes is how many requests are in flight at once, so the load finishes in a fraction of the time the same writes would take one after another. Elapsed time is bounded by the container's provisioned throughput, which is why ingest jobs raise RU/s during a load and lower it afterward.

---

## Clean up resources

When you finish the course, delete the resource group only if you created it and every resource in it can be removed. If your lab provided `ResourceGroup1`, skip this command and delete only the exercise resources you no longer need:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name <your-account-name> --resource-group $resourceGroup --yes
```
