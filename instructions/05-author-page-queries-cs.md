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

# Author and Page Queries in C#

In this exercise, you query the CosmicWorks catalog using parameters, projections, array subqueries, joins, and continuation tokens. You also record request charges to compare query costs.

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
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 request units per second (RU/s), loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Connect to the CosmicWorks catalog

The setup script loads 295 CosmicWorks products into `product`. Each product has the following structure:

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

    // Reuse one client for all queries.
    CosmosClient client = new(endpoint, new DefaultAzureCredential());

    Container container = client.GetContainer("cosmicworks", "product");

    Console.WriteLine("Container ready.");
    ```

1. Add the following records at the end of **Program.cs**. Keep all executable code above these declarations throughout the exercise:

    ```csharp
    // Property names and nested tag objects match the stored JSON shape.
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

1. Run the project:

    ```bash
    dotnet run
    ```

---

## Task 2: Write a parameterized, projected query

Query a category with price and name-prefix filters, then project the result for a product card. Run the same query with and without an explicit partition key in the request.

The category for this task is **Components, Road Frames**, which holds 33 products.

> &#128161; Each task adds code to the same file. Later runs also execute queries from the earlier tasks.

1. Append the following code, above the record declarations. It defines the query with three parameters:

    ```csharp
    const string roadFrames = "3E4CEACD-D007-46EB-82D7-31F6141752B2";

    // Project the fields needed for a product card.
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

    // Bind values separately from SQL instead of interpolating user input.
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
        // Keep SQL and parameters identical; only request scoping changes.
        QueryRequestOptions options = new();
        if (key.HasValue) options.PartitionKey = key.Value;

        int count = 0;
        double charge = 0;

        using FeedIterator<ProductCard> iterator =
            container.GetItemQueryIterator<ProductCard>(q, requestOptions: options);

        // Count results and RU charges across every response page.
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
    // These types describe the query's projection, not the full stored Product.
    public record ScannerData(double price);

    public record ProductCard(string name, string category, ScannerData scannerData);
    ```

1. Run the project and compare the two charges:

    ```bash
    dotnet run
    ```

Both calls return the same 12 products and should have similar charges. The SQL includes an equality filter on `categoryId`, so Azure Cosmos DB can route either request to that partition. Passing the partition key in the request makes the intended scope explicit.

---

## Task 3: Reach into the tags array with a subquery

Filter products by what their nested `tags` array contains, and project a trimmed version of that array alongside each result.

Each product's `tags` array contains objects with `id` and `name` properties, such as `Tag-30`. Products can have multiple tags, and the same tag can appear on multiple products.

1. Append the following code. `EXISTS` filters items by the contents of the array, and the `ARRAY` expression projects the tag names alongside each match:

    ```csharp
    // EXISTS decides which products match. ARRAY shapes the tags returned for
    // each match, without producing a separate result row for every tag.
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

The query returns four products with `Tag-30`. Each product appears once, and `tagNames` contains all of its tags.

Now narrow the projection. The `ARRAY` subquery can carry its own `WHERE` clause, separate from the one on the outer query.

1. In the `subquery` definition, replace the `ARRAY(...) AS tagNames` line with the following line:

    ```csharp
    ARRAY(SELECT VALUE t.name FROM t IN p.tags WHERE t.name = @tag) AS tagNames
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

The same four products come back, but each `tagNames` array now holds `Tag-30` alone. The outer `WHERE` clause selects products; the `WHERE` clause inside `ARRAY` selects the tags included in each result.

---

## Task 4: Expand the array with a cross-product query

Use a `JOIN` to return one row per tag rather than one row per product.

1. Append the following code. It expands every tag in the category and counts both the rows returned and the distinct products behind them:

    ```csharp
    // Expand each product into one row per tag; empty arrays produce no rows.
    QueryDefinition crossProduct = new QueryDefinition("""
            SELECT p.name, t.name AS tag
            FROM product p
            JOIN t IN p.tags
            WHERE p.categoryId = @category
            """)
        .WithParameter("@category", roadFrames);

    // Count distinct product names separately from product/tag pairs.
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

The query returns 98 product-tag rows from 29 of the 33 products. Four products have empty `tags` arrays, so they contribute no rows.

Compare the results for three products with empty `tags` arrays.

1. Append the following code. The first query finds the products by name, and the second runs the identical filter through a `JOIN`:

    ```csharp
    string[] untagged = { "Road Tire Tube", "Classic Vest, S", "ML Mountain Pedal" };

    // SELECT VALUE returns scalar strings, so the iterator below uses string.
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

The direct query returns three products; the `JOIN` returns none because all three have empty `tags` arrays. A `JOIN` over `tags` excludes all 45 products in the catalog that have empty tag arrays.

When a result must include every product regardless of its tags, keep the array out of the `FROM` clause and project it instead, with the `ARRAY` expression from Task 3.

---

## Task 5: Page a result set with continuation tokens

Request pages of up to 10 items and use continuation tokens to retrieve subsequent pages.

1. Append the following code. The method fetches exactly one page and returns the token for the next one:

    ```csharp
    async Task<(int Count, double Charge, string? Token)> GetPageAsync(string? continuationToken)
    {
        QueryDefinition paged = new QueryDefinition(
                "SELECT p.id, p.name, p.price FROM product p WHERE p.categoryId = @category")
            .WithParameter("@category", roadFrames);

        // MaxItemCount requests a page size; fewer items can arrive even when
        // a continuation token still indicates more results.
        QueryRequestOptions options = new()
        {
            PartitionKey = new PartitionKey(roadFrames),
            MaxItemCount = 10
        };

        // Reuse the opaque token with the same query, parameters, and partition scope.
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
    // Stop on token exhaustion, not on a short or empty page.
    while (token is not null);
    ```

    The first request starts without a token. Paging ends when the response has no continuation token.

1. Run the project:

    ```bash
    dotnet run
    ```

Test paging with an ordered query:

1. In `GetPageAsync`, add `ORDER BY p.price` to the end of the query text:

    ```csharp
    "SELECT p.id, p.name, p.price FROM product p WHERE p.categoryId = @category ORDER BY p.price"
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

Sorted queries also support continuation tokens.

Then test an aggregate query:

1. In `GetPageAsync`, replace the query text with the following aggregate, which drops the `ORDER BY` clause you added:

    ```csharp
    "SELECT COUNT(1) FROM product p WHERE p.categoryId = @category"
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

The aggregate returns one count result, so this example finishes after one page.

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
