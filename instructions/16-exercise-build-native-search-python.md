---
lab:
  title: Build Native Search Over a Product Catalog in Python
  module: Module 16 - Implement Full-Text and Vector Search in Azure Cosmos DB for NoSQL
  description: Load the CosmicWorks catalog with searchable text and embeddings, run BM25 and VectorDistance queries against one container, and refresh a stale embedding from the change feed.
  duration: 60 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Build Native Search Over a Product Catalog in Python

In this exercise, you add full-text and vector search to a CosmicWorks product catalog in Azure Cosmos DB for NoSQL. You load searchable text and embeddings, run keyword and similarity queries, and use the change feed to refresh an embedding after renaming a product.

The setup script configures the container's full-text and vector policies and indexes. Your application prepares the searchable text and generates the embeddings.

This exercise takes approximately **60** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

The setup script creates a Microsoft Foundry resource, project, and `text-embedding-3-small` deployment. Your subscription needs quota for that model in the Foundry region. You don't need an existing Foundry project.

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

1. Sign in to the Azure CLI and follow the sign-in prompt.

    ```azurecli
    az login
    ```

1. Set variables for the resource group and region. If your lab environment provides a resource group, use that name. Otherwise, use a new group that contains only this exercise's resources.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "eastus"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab16 -LabProfile search -AccountOnly -EnableFoundry -EmbeddingOnly -FoundryLocation $location
    ```

    The script generates a globally unique account name, such as `dp420lab16a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name**, **Account endpoint**, **Foundry account**, and **OpenAI endpoint** values the script prints. The Cosmos DB endpoint looks like `https://<your-account-name>.documents.azure.com:443/`. The script also saves the Foundry values in `logs/foundry-<account-name>.json`.

1. Set the account name the script printed, then open that account in the [Azure portal](https://portal.azure.com).

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Under **Settings**, select **Features**. Confirm **Vector Search for NoSQL API** is enabled, then enable **Full Text & Hybrid Search for NoSQL API**. Allow up to 15 minutes for enrollment. Confirm both features are enabled before continuing.

1. Complete setup and verify the resources using the account name you recorded.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -AccountName $accountName -LabProfile search -SearchFeaturesReady -EnableFoundry -EmbeddingOnly -FoundryLocation $location
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile search -EnableFoundry -EmbeddingOnly
    ```

    Continue after both commands succeed.

After both stages, the script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled and the `EnableNoSQLVectorSearch` capability |
| `cosmicworks` database | Holds the container this exercise uses |
| `productSearch` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, empty. Full-text policy and index on `/searchText`, vector policy and `diskANN` index on `/embedding` at 1,536 dimensions with cosine distance |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |
| Microsoft Foundry resource and project | Key-based authentication disabled; project named `dp420` |
| Embedding deployment | `text-embedding-3-small`, version `1`, Standard deployment, 30 capacity units; produces 1,536-dimensional embeddings by default |
| Foundry role assignment | Foundry User, granted to your signed-in identity on the Foundry resource |

The applications use `DefaultAzureCredential` for Microsoft Entra ID authentication. It can select another configured identity before your Azure CLI identity, so ensure the selected identity has the roles listed above.

> &#9888; Use only the resource group and account this script creates. Vector indexing and search can't be disabled on a container after enablement, and vector policy settings can't be edited directly. Never point this exercise at a shared training or production account.

1. Set variables for the account name and its endpoint so later commands can use them.

    ```powershell
    $accountName = "<your-account-name>"
    $cosmosEndpoint = "https://$accountName.documents.azure.com:443/"
    ```

## Task 1: Confirm the embedding deployment

Confirm that the `text-embedding-3-small` deployment is ready before loading the catalog.

1. In the **Allfiles/Labs/Shared** terminal, load the saved settings.

    ```powershell
    $foundry = Get-Content "./logs/foundry-$accountName.json" -Raw | ConvertFrom-Json
    $openAiName = $foundry.FoundryAccountName
    $openAiEndpoint = $foundry.OpenAiEndpoint
    $foundry | Format-List FoundryAccountName, OpenAiEndpoint, EmbeddingDeployment, EmbeddingDimensions
    ```

1. Check the deployed model's state.

    ```azurecli
    az cognitiveservices account deployment list `
        --name $openAiName `
        --resource-group $resourceGroup `
        --query "[].{Deployment:name,Model:properties.model.name,Version:properties.model.version,State:properties.provisioningState}" `
        --output table
    ```

    Confirm that `text-embedding-3-small` reports `Succeeded`. Use **OpenAiEndpoint**, not the project endpoint, in the application code that follows. The model's default output length matches the container's 1,536 dimensions.

> &#128221; New role assignments can take several minutes to take effect.

## Task 2: Load the catalog with searchable text and embeddings

Combine each product's name and category into `searchText`, then generate an embedding from that text. These fields provide more useful search terms than the catalog's generated descriptions. Store the text in `/searchText` and the vector in `/embedding`, which are the paths configured in the container's indexes.

1. Create a folder for the application and open it in the integrated terminal.

    ```powershell
    mkdir search-lab
    cd search-lab
    ```

1. Create and activate a virtual environment.

    ```powershell
    python -m venv .venv
    .venv\Scripts\activate
    ```

    On Linux or macOS, activate the environment with `source .venv/bin/activate`.

1. Install the packages the exercise uses.

    ```powershell
    pip install azure-cosmos azure-identity openai
    ```

1. Create a file named **load.py** and add the following code. Replace the two placeholder values with your endpoints.

    ```python
    import hashlib
    import json
    import urllib.request

    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    COSMOS_ENDPOINT = "<cosmos-endpoint>"
    OPENAI_ENDPOINT = "<openai-endpoint>"
    DEPLOYMENT = "text-embedding-3-small"
    DATA_URL = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product"

    # Reuse a credential for both services. The token provider requests
    # the Azure OpenAI audience, not the Cosmos DB audience.
    credential = DefaultAzureCredential()

    openai_client = AzureOpenAI(
        azure_endpoint=OPENAI_ENDPOINT,
        azure_ad_token_provider=get_bearer_token_provider(
            credential, "https://cognitiveservices.azure.com/.default"
        ),
        api_version="2024-10-21",
    )

    container = (
        CosmosClient(COSMOS_ENDPOINT, credential)
        .get_database_client("cosmicworks")
        .get_container_client("productSearch")
    )


    def build_search_text(product):
        # Both keyword search and embeddings use this same text representation.
        return f"{product['name']} {product['categoryName']}"


    def content_hash(text):
        # Detect changes to the embedding input without comparing entire vectors.
        return hashlib.sha256(text.encode("utf-8")).hexdigest()


    with urllib.request.urlopen(DATA_URL) as response:
        products = json.load(response)

    print(f"Downloaded {len(products)} products.")

    # Batch embedding requests, then write the enriched products individually.
    # This isn't a Cosmos DB transactional batch.
    for start in range(0, len(products), 50):
        batch = products[start:start + 50]
        texts = [build_search_text(product) for product in batch]

        embeddings = openai_client.embeddings.create(input=texts, model=DEPLOYMENT)

        # Keep each vector with its source text and original product identity.
        for product, text, data in zip(batch, texts, embeddings.data):
            product["searchText"] = text
            product["contentHash"] = content_hash(text)
            product["embedding"] = data.embedding
            container.upsert_item(product)

        print(f"Loaded {start + len(batch)} of {len(products)}.")
    ```

1. Run the application.

    ```powershell
    python load.py
    ```

    ```output
    Downloaded 295 products.
    Loaded 50 of 295.
    Loaded 100 of 295.
    Loaded 150 of 295.
    Loaded 200 of 295.
    Loaded 250 of 295.
    Loaded 295 of 295.
    ```

Each product now has `searchText`, an `embedding`, and a `contentHash`. Task 5 uses the hash to detect changes to the embedding input.

## Task 3: Search the catalog with BM25 ranking

Use full-text functions to match search terms and rank products by relevance.

1. In the [Azure portal](https://portal.azure.com), open your Azure Cosmos DB account, select **Data Explorer**, and expand the `cosmicworks` database.

1. Right-click the `productSearch` container and select **New SQL Query**. Run the following query, which finds every item whose searchable text contains the term.

    ```sql
    SELECT c.name, c.categoryName, c.price
    FROM c
    WHERE FullTextContains(c.searchText, "helmet")
    ```

    The catalog holds exactly three helmets, all in the same category and all at the same price.

    ```output
    [
      { "name": "Sport-100 Helmet, Black", "categoryName": "Accessories, Helmets", "price": 34.99 },
      { "name": "Sport-100 Helmet, Blue",  "categoryName": "Accessories, Helmets", "price": 34.99 },
      { "name": "Sport-100 Helmet, Red",   "categoryName": "Accessories, Helmets", "price": 34.99 }
    ]
    ```

    Note that the category reads *Helmets* while the search term is *helmet*. Stemming is why the plural matches the singular.

1. Run the following query, which requires both terms.

    ```sql
    SELECT VALUE COUNT(1)
    FROM c
    WHERE FullTextContainsAll(c.searchText, "mountain", "helmet")
    ```

    ```output
    [
      0
    ]
    ```

    No CosmicWorks product is both a mountain product and a helmet, so requiring both terms eliminates the whole catalog.

1. Change the function to `FullTextContainsAny` and run it again.

    ```sql
    SELECT VALUE COUNT(1)
    FROM c
    WHERE FullTextContainsAny(c.searchText, "mountain", "helmet")
    ```

    This query counts products that match either term, including mountain products and the three helmets. Record the count.

1. Rank results by relevance instead of filtering them.

    ```sql
    SELECT TOP 10 c.name, c.categoryName
    FROM c
    ORDER BY RANK FullTextScore(c.searchText, "mountain", "frame")
    ```

    Items that carry both terms sort above items that carry one.

1. Run the following query, which adds `FullTextScore` to the `SELECT` list.

    ```sql
    SELECT TOP 10 c.name, c.categoryName,
        FullTextScore(c.searchText, "mountain", "frame") AS score
    FROM c
    ORDER BY RANK FullTextScore(c.searchText, "mountain", "frame")
    ```

    This query is expected to fail because `FullTextScore` can appear only in an `ORDER BY RANK` clause.

1. Remove `FullTextScore` from the `SELECT` list and keep it in `ORDER BY RANK`. Run the corrected query.

    ```sql
    SELECT TOP 10 c.name, c.categoryName
    FROM c
    ORDER BY RANK FullTextScore(c.searchText, "mountain", "frame")
    ```

    The query returns products ranked by relevance without including the score in the results.

1. Compare the request charges for full-text search and substring matching. Run each of the following queries, and after each one open the **Query Stats** tab and record the **Request Charge**.

    ```sql
    SELECT VALUE COUNT(1) FROM c WHERE FullTextContains(c.searchText, "helmet")
    ```

    ```sql
    SELECT VALUE COUNT(1) FROM c WHERE CONTAINS(c.searchText, "Helmet")
    ```

    Request charges can be similar for this small catalog. `FullTextContains` uses the full-text index to match tokens, while `CONTAINS` matches literal substrings, so the results can differ.

## Task 4: Search the catalog by meaning

Search for products by meaning rather than exact keywords.

1. Create a file named **search.py** and add the following code, replacing the two placeholder values with your endpoints.

    ```python
    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    COSMOS_ENDPOINT = "<cosmos-endpoint>"
    OPENAI_ENDPOINT = "<openai-endpoint>"
    DEPLOYMENT = "text-embedding-3-small"

    credential = DefaultAzureCredential()

    openai_client = AzureOpenAI(
        azure_endpoint=OPENAI_ENDPOINT,
        azure_ad_token_provider=get_bearer_token_provider(
            credential, "https://cognitiveservices.azure.com/.default"
        ),
        api_version="2024-10-21",
    )

    container = (
        CosmosClient(COSMOS_ENDPOINT, credential)
        .get_database_client("cosmicworks")
        .get_container_client("productSearch")
    )

    search_text = "something to protect my head"

    # Use the same embedding deployment as ingestion so query and stored vectors
    # share a vector space and match the container's configured dimensions.
    response = openai_client.embeddings.create(input=search_text, model=DEPLOYMENT)
    query_vector = response.data[0].embedding

    # Although the alias says similarityScore, the projected value is a distance.
    # ORDER BY returns the nearest vectors first; it isn't a confidence percentage.
    query = """
        SELECT TOP 5 c.name, c.categoryName,
            VectorDistance(c.embedding, @queryVector) AS similarityScore
        FROM c
        ORDER BY VectorDistance(c.embedding, @queryVector)
    """

    results = container.query_items(
        query=query,
        parameters=[{"name": "@queryVector", "value": query_vector}],
    )

    print(f'Query: "{search_text}"')
    for item in results:
        print(f"  {item['similarityScore']:.4f}  {item['name']}")

    print(f"Request charge: {container.client_connection.last_response_headers['x-ms-request-charge']} RUs")
    ```

1. Run the application.

    ```powershell
    python search.py
    ```

Record the five product names and distance scores. The phrase doesn't contain *helmet*, but helmet products should appear among the closest matches. Lower distances indicate closer matches.

1. Add a metadata filter by replacing the SQL text inside the existing `query` string with the following query. The new `@categoryId` parameter is bound in the next step.

    ```sql
    SELECT TOP 5 c.name, c.price,
        VectorDistance(c.embedding, @queryVector) AS similarityScore
    FROM c
    WHERE c.categoryId = @categoryId
    ORDER BY VectorDistance(c.embedding, @queryVector)
    ```

1. Bind `@categoryId` to the helmet category identifier. Replace the existing `results = container.query_items(...)` call with the following code, which keeps the query vector parameter and adds the category parameter.

    ```python
    results = container.query_items(
        query=query,
        parameters=[
            {"name": "@queryVector", "value": query_vector},
            {"name": "@categoryId", "value": "14A1AD5D-59EA-4B63-A189-67B077783B0E"},
        ],
    )
    ```

    Run the application again with `python search.py` and compare the request charge with the unfiltered query.

    Filtering on `categoryId`, the partition key, limits the search to one logical partition. The request charge might not decrease on this small dataset.

> &#128221; The `diskANN` index requires at least 1,000 vectors. With only 295 vectors, these queries use a full scan.

## Task 5: Refresh an embedding from the change feed

Renaming a product doesn't update its stored `searchText` or embedding. The full-text index updates when the application writes a new `searchText` value. In this task, you rename a product, then run a change feed consumer that finds the mismatch and repairs it.

1. In the portal **Data Explorer**, run the following query and record the identifier and category of the first result.

    ```sql
    SELECT c.id, c.categoryId, c.name, c.searchText
    FROM c
    WHERE c.name = "Sport-100 Helmet, Red"
    ```

1. In the **Data Explorer** tree, expand the `productSearch` container under `cosmicworks` and select **Items**.

1. In the filter field, enter the following filter, replacing `<product-id>` with the `id` you recorded from the query result. Select **Apply**.

    ```sql
    WHERE c.id = "<product-id>"
    ```

1. Select the matching item in the filtered list. In the JSON editor, change only its `name` value to `Sport-100 Head Protector, Red`, then select **Update**.

1. Confirm the mismatch. Run the following query in **Data Explorer** and compare `name` against `searchText`.

    ```sql
    SELECT c.id, c.categoryId, c.name, c.searchText
    FROM c
    WHERE c.name = "Sport-100 Head Protector, Red"
    ```

    The name changed, but `searchText` still contains the old name. The stored embedding hasn't been regenerated either.

1. Create a file named **refresh.py** and add the following code, replacing the two placeholder values with your endpoints.

    ```python
    import hashlib

    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    COSMOS_ENDPOINT = "<cosmos-endpoint>"
    OPENAI_ENDPOINT = "<openai-endpoint>"
    DEPLOYMENT = "text-embedding-3-small"

    credential = DefaultAzureCredential()

    openai_client = AzureOpenAI(
        azure_endpoint=OPENAI_ENDPOINT,
        azure_ad_token_provider=get_bearer_token_provider(
            credential, "https://cognitiveservices.azure.com/.default"
        ),
        api_version="2024-10-21",
    )

    container = (
        CosmosClient(COSMOS_ENDPOINT, credential)
        .get_database_client("cosmicworks")
        .get_container_client("productSearch")
    )


    def build_search_text(product):
        return f"{product['name']} {product['categoryName']}"


    def content_hash(text):
        return hashlib.sha256(text.encode("utf-8")).hexdigest()


    scanned = 0
    refreshed = 0

    # This one-off scan starts at the beginning; it doesn't persist a checkpoint.
    for page in container.query_items_change_feed(start_time="Beginning").by_page():
        for change in page:
            scanned += 1
            text = build_search_text(change)

            # Skip unchanged embedding inputs, including this refresher's own writes.
            if content_hash(text) == change.get("contentHash"):
                continue

            response = openai_client.embeddings.create(input=text, model=DEPLOYMENT)

            # Refresh text, hash, and vector together so the search fields agree.
            change["searchText"] = text
            change["contentHash"] = content_hash(text)
            change["embedding"] = response.data[0].embedding
            container.upsert_item(change)

            refreshed += 1
            print(f"Refreshed: {change['name']}")

    print(f"Scanned {scanned} changes, refreshed {refreshed}.")
    ```

1. Run the application.

    ```powershell
    python refresh.py
    ```

    Example output (the scanned count can vary):

    ```output
    Refreshed: Sport-100 Head Protector, Red
    Scanned 295 changes, refreshed 1.
    ```

    Latest-version mode returns the latest version of each changed item, not every intermediate write. The scan can include the consumer's own update, so the scanned count can exceed 295. Only the renamed product should need a refresh.

1. Run the consumer a second time without changing anything.

    ```output
    Scanned 295 changes, refreshed 0.
    ```

    The stored hashes now match the product text, so no embeddings are regenerated. The hash check also prevents unnecessary embedding calls when the consumer reads its own updates.

1. Confirm the repair. In the portal **Data Explorer**, run the following query.

    ```sql
    SELECT c.id, c.categoryId, c.name, c.searchText
    FROM c
    WHERE c.name = "Sport-100 Head Protector, Red"
    ```

    Check that `searchText` now *contains* the new name, `Sport-100 Head Protector, Red`.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains no resources you need to keep. This removes the Cosmos DB account, Foundry resource, project, and model deployment:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, keep it. Delete only the Cosmos DB and Foundry resources you created for this exercise, after confirming that no other application uses them:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
az cognitiveservices account delete --name $openAiName --resource-group $resourceGroup
```
