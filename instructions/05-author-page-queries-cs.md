---
lab:
  title: Author and Page Queries in C#
  module: Module 5 - Query Data in Azure Cosmos DB for NoSQL
  description: Load the CosmicWorks catalog, write parameterized and projected queries with built-in functions, add a correlated subquery and a cross-product query, and page results with continuation tokens.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you build a query layer against an Azure Cosmos DB for NoSQL catalog container and run every query technique from this module. You load the CosmicWorks product catalog, then write a parameterized query that projects a custom shape. You reach into a nested tags array with a correlated subquery, expand that array with a cross-product query, and finish by paging a result set with continuation tokens. Throughout, you print the request charge so you can see what each choice costs.

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

1. Set variables for the resource group (If your lab environment provided a resource group, use that name) and region you want to use. Change either value if you prefer a different resource group name or region.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab05 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab05a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint throughout this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds every container this learning path uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 request units per second (RU/s), loaded with the 295 CosmicWorks products every query in this exercise runs against |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Connect to the CosmicWorks catalog

Every query in this exercise runs against the same data: the product catalog from the CosmicWorks sample, which the setup script already loaded into the `product` container.

The catalog holds 295 products. Each one looks like this:

```json
{
    "id": "027D0B9A-F9D9-4C96-8213-C8546C4AAE71",
    "categoryId": "26C74104-40BC-4541-8EF5-9892F7F03D72",
    "categoryName": "Components, Saddles",
    "sku": "SE-R581",
    "name": "LL Road Seat/Saddle",
    "description": "The product called \"LL Road Seat/Saddle\"",
    "price": 27.12,
    "tags": [
        { "id": "0573D684-9140-4DEE-89AF-4E4A90E65666", "name": "Tag-113" },
        { "id": "6C2F05C8-1E61-4912-BE1A-C67A378429BB", "name": "Tag-5" },
        { "id": "B48D6572-67EB-4630-A1DB-AFD4AD7041C9", "name": "Tag-100" },
        { "id": "D70F215D-A8AC-483A-9ABD-4A008D2B72B2", "name": "Tag-85" },
        { "id": "DCF66D9A-E2BF-4C70-8AC1-AD55E5988E9D", "name": "Tag-37" }
    ]
}
```

`categoryId` is the partition key. `tags` is the nested array that Tasks 3 and 4 query, and 45 of the 295 products carry an empty one.

1. Open a terminal and create a new console project:

    ```bash
    dotnet new console -n cosmos-queries-exercise
    cd cosmos-queries-exercise
    ```

1. Add the SDK packages:

    ```bash
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Newtonsoft.Json
    dotnet add package Azure.Identity
    ```

1. Open **Program.cs** and replace its contents with the following code. Set `endpoint` to the account endpoint the setup script printed:

    ```csharp
    using System.Text.Json;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";

    CosmosClient client = new(endpoint, new DefaultAzureCredential());

    Container container = client.GetContainer("cosmicworks", "product");

    Console.WriteLine("Container ready.");
    ```

    `GetContainer` builds a client-side reference without calling the service. Creating a database or container is a control-plane operation, which a Cosmos DB data-plane role can't perform, so the setup script created them for you.

1. Add the item types at the bottom of the file. Top-level statements come first, so every type declaration in this exercise belongs below the executable code:

    ```csharp
    public record Tag(string id, string name);

    public record Product(
        string id,
        string categoryId,
        string categoryName,
        string sku,
        string name,
        string description,
        double price,
        Tag[] tags);
    ```

    The record property names match the JSON exactly, so no naming policy is needed.

1. Run the project:

    ```bash
    dotnet run
    ```

---

## Task 2: Write a parameterized, projected query

Query one category with a price filter and a prefix match, then project the result into the shape a product card needs. Compare what the query costs when it's scoped to the partition key against what it costs cross-partition.

The category for this task is **Components, Road Frames**, which holds 33 products.

> &#128161; Each task appends to the same file, so every run repeats the queries from the earlier tasks. Comment out the earlier queries once you see their output.

1. Append the following code, above the record declarations. It defines the query with three parameters:

    ```csharp
    const string roadFrames = "3E4CEACD-D007-46EB-82D7-31F6141752B2";

    string sql = """
        SELECT
            p.name,
            p.categoryName AS category,
            { "price": p.price } AS scannerData
        FROM product p
        WHERE p.categoryId = @category
          AND p.price <= @max
          AND STARTSWITH(p.name, @prefix, true)
        """;

    QueryDefinition query = new QueryDefinition(sql)
        .WithParameter("@category", roadFrames)
        .WithParameter("@max", 400)
        .WithParameter("@prefix", "ll");
    ```

    The object literal creates the nested `scannerData` object in the output, and the third argument to `STARTSWITH` makes the prefix match case-insensitive.

1. Add a helper that runs the query and returns its total charge, then call it twice: once scoped to the partition key and once without:

    ```csharp
    async Task<(int Count, double Charge)> RunAsync(QueryDefinition q, PartitionKey? key)
    {
        QueryRequestOptions options = new();
        if (key.HasValue) options.PartitionKey = key.Value;

        int count = 0;
        double charge = 0;

        using FeedIterator<ProductCard> iterator =
            container.GetItemQueryIterator<ProductCard>(q, requestOptions: options);

        while (iterator.HasMoreResults)
        {
            FeedResponse<ProductCard> page = await iterator.ReadNextAsync();
            count += page.Count;
            charge += page.RequestCharge;
        }

        return (count, charge);
    }

    var scoped = await RunAsync(query, new PartitionKey(roadFrames));
    var unscoped = await RunAsync(query, null);

    Console.WriteLine($"Scoped:      {scoped.Count} items, {scoped.Charge:0.00} RU");
    Console.WriteLine($"Cross-part.: {unscoped.Count} items, {unscoped.Charge:0.00} RU");
    ```

1. Add the result types to the record declarations at the bottom of the file:

    ```csharp
    public record ScannerData(double price);

    public record ProductCard(string name, string category, ScannerData scannerData);
    ```

    The result type matches the projection, not the stored item. A query that returns three fields deserializes into a type with three properties.

1. Run the project and compare the two charges:

    ```bash
    dotnet run
    ```

Both calls return the same 12 products, and the two charges are close to identical. This container's autoscale maximum of 1,000 RU/s puts it on a single physical partition, so the unscoped query has only that one partition to reach. Setting the partition key scopes a query to one physical partition; without it, the service fans out the query to every physical partition and merges the results, so the saving grows with the number of partitions the container spans. In a catalog API, the category is always known, so the partition key always belongs on the request.

---

## Task 3: Reach into the tags array with a subquery

Filter products by what their nested `tags` array contains, and project a trimmed version of that array alongside each result.

CosmicWorks tags are merchandising-assigned identifiers rather than descriptive words. A tag is an object with an `id` and a `name` such as `Tag-30`. The same tag appears on many products, and a product can carry several. A catalog often works that way in practice: the label is a key into a merchandising system, and the query matches it exactly.

1. Append the following code. `EXISTS` filters items by the contents of the array, and the `ARRAY` expression projects the tag names alongside each match:

    ```csharp
    QueryDefinition subquery = new QueryDefinition("""
            SELECT
                p.id,
                p.name,
                ARRAY(SELECT VALUE t.name FROM t IN p.tags) AS tagNames
            FROM product p
            WHERE p.categoryId = @category
              AND EXISTS (SELECT VALUE t FROM t IN p.tags WHERE t.name = @tag)
            """)
        .WithParameter("@category", roadFrames)
        .WithParameter("@tag", "Tag-30");

    int rows = 0;
    double subqueryCharge = 0;

    using (FeedIterator<TaggedItem> iterator = container.GetItemQueryIterator<TaggedItem>(
        subquery,
        requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(roadFrames) }))
    {
        while (iterator.HasMoreResults)
        {
            FeedResponse<TaggedItem> page = await iterator.ReadNextAsync();
            subqueryCharge += page.RequestCharge;

            foreach (TaggedItem item in page)
            {
                Console.WriteLine($"{item.name}: [{string.Join(", ", item.tagNames)}]");
                rows++;
            }
        }
    }

    Console.WriteLine($"EXISTS:      {rows} items, {subqueryCharge:0.00} RU");
    ```

1. Add the result type to the record declarations:

    ```csharp
    public record TaggedItem(string id, string name, string[] tagNames);
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

Four products in this category carry `Tag-30`, and each one appears exactly once, no matter how many other tags it holds. The `tagNames` array lists every tag on those products, including the ones the filter never mentions.

Now narrow the projection. The `ARRAY` subquery can carry its own `WHERE` clause, separate from the one on the outer query.

1. In the `subquery` definition, replace the `ARRAY(...) AS tagNames` line with the following line:

    ```csharp
    ARRAY(SELECT VALUE t.name FROM t IN p.tags WHERE t.name = @tag) AS tagNames
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

The same four products come back, but each `tagNames` array now holds `Tag-30` alone. The outer `WHERE` clause decides which products the query returns, and the `WHERE` clause inside the `ARRAY` subquery decides what each returned array holds. Filtering items and shaping their arrays are separate decisions.

---

## Task 4: Expand the array with a cross-product query

Ask a different question of the same data. A `JOIN` returns one result per array element rather than one result per product, which is the shape tag report needs.

1. Append the following code. It expands every tag in the category and counts both the rows returned and the distinct products behind them:

    ```csharp
    QueryDefinition crossProduct = new QueryDefinition("""
            SELECT p.name, t.name AS tag
            FROM product p
            JOIN t IN p.tags
            WHERE p.categoryId = @category
            """)
        .WithParameter("@category", roadFrames);

    HashSet<string> namesInJoin = new();
    int pairs = 0;
    double joinCharge = 0;

    using (FeedIterator<TagPair> iterator = container.GetItemQueryIterator<TagPair>(
        crossProduct,
        requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(roadFrames) }))
    {
        while (iterator.HasMoreResults)
        {
            FeedResponse<TagPair> page = await iterator.ReadNextAsync();
            joinCharge += page.RequestCharge;

            foreach (TagPair pair in page)
            {
                namesInJoin.Add(pair.name);
                pairs++;
            }
        }
    }

    Console.WriteLine($"JOIN:        {pairs} rows from {namesInJoin.Count} products, {joinCharge:0.00} RU");
    ```

1. Add the result type to the record declarations:

    ```csharp
    public record TagPair(string name, string tag);
    ```

1. Run the project.

The query returns 98 rows drawn from 29 products, in a category that holds 33. Four products never appear. No predicate excludes them, because the query has none beyond the category. They carry an empty `tags` array, and the cross-product of a value with an empty set is empty.

Now watch the same effect against three products elsewhere in the catalog that carry no tags at all.

1. Append the following code. The first query finds the products by name, and the second runs the identical filter through a `JOIN`:

    ```csharp
    string[] untagged = { "Road Tire Tube", "Classic Vest, S", "ML Mountain Pedal" };

    QueryDefinition direct = new QueryDefinition(
            "SELECT VALUE p.name FROM product p WHERE ARRAY_CONTAINS(@names, p.name)")
        .WithParameter("@names", untagged);

    QueryDefinition joined = new QueryDefinition("""
            SELECT VALUE p.name
            FROM product p
            JOIN t IN p.tags
            WHERE ARRAY_CONTAINS(@names, p.name)
            """)
        .WithParameter("@names", untagged);

    async Task<int> CountAsync(QueryDefinition q)
    {
        int total = 0;

        using FeedIterator<string> iterator = container.GetItemQueryIterator<string>(q);

        while (iterator.HasMoreResults)
        {
            total += (await iterator.ReadNextAsync()).Count;
        }

        return total;
    }

    Console.WriteLine($"Without JOIN: {await CountAsync(direct)} products");
    Console.WriteLine($"With JOIN:    {await CountAsync(joined)} products");
    ```

1. Run the project.

The first query returns all three products. The second returns none, even though both queries apply the same filter to the same items. The `JOIN` removes every product with an empty `tags` array before the filter runs. Nothing in the response warns you that those products dropped out, so a report built on a `JOIN` counts only the products that hold at least one tag. In this catalog, 45 of the 295 products disappear that way because their `tags` arrays are empty.

When a result must include every product regardless of its tags, keep the array out of the `FROM` clause and project it instead, with the `ARRAY` expression from Task 3.

---

## Task 5: Page a result set with continuation tokens

Serve one category 10 items at a time, the way a stateless API does, resuming each page from the token the previous page returned.

1. Append the following code. The method fetches exactly one page and returns the token for the next one:

    ```csharp
    async Task<(int Count, double Charge, string? Token)> GetPageAsync(string? continuationToken)
    {
        QueryDefinition paged = new QueryDefinition(
                "SELECT p.id, p.name, p.price FROM product p WHERE p.categoryId = @category")
            .WithParameter("@category", roadFrames);

        QueryRequestOptions options = new()
        {
            PartitionKey = new PartitionKey(roadFrames),
            MaxItemCount = 10
        };

        using FeedIterator<PagedProduct> iterator =
            container.GetItemQueryIterator<PagedProduct>(paged, continuationToken, options);

        FeedResponse<PagedProduct> page = await iterator.ReadNextAsync();

        return (page.Count, page.RequestCharge, page.ContinuationToken);
    }
    ```

1. Add the result type to the record declarations:

    ```csharp
    public record PagedProduct(string id, string name, double price);
    ```

1. Add a loop that walks the pages, passing each token into the next request:

    ```csharp
    string? token = null;
    int pageNumber = 0;

    do
    {
        var result = await GetPageAsync(token);
        token = result.Token;
        pageNumber++;

        Console.WriteLine($"Page {pageNumber}: {result.Count} items, {result.Charge:0.00} RU, token: {(token is null ? "none" : "present")}");
    }
    while (token is not null);
    ```

    The first request passes `null` and starts at the beginning. A `null` token in the response means the results are exhausted, which is why the loop tests the token rather than the item count.

1. Run the project:

    ```bash
    dotnet run
    ```

Watch the item counts. Most pages return 10 items, but the service can return fewer at any point and still have more results waiting. The token, not the count, is what tells you whether to ask again.

Two limits are worth confirming yourself. Start with sorting.

1. In `GetPageAsync`, add `ORDER BY p.price` to the end of the query text:

    ```csharp
    "SELECT p.id, p.name, p.price FROM product p WHERE p.categoryId = @category ORDER BY p.price"
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

Paging still works. The service resumes a sorted result set the same way it resumes an unsorted one, so a token survives an `ORDER BY` clause.

Now try an aggregate instead.

1. In `GetPageAsync`, replace the query text with the following aggregate, which drops the `ORDER BY` clause you added:

    ```csharp
    "SELECT COUNT(1) FROM product p WHERE p.categoryId = @category"
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

This time the loop ends after one page. The aggregate returns a single result and no usable token, because it scans every matching item before it can produce an answer and can't checkpoint partway through that calculation.

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
