---
lab:
  title: Build Native Search Over a Product Catalog in Python
  module: Module 16 - Implement Full-Text and Vector Search in Azure Cosmos DB for NoSQL
  description: Load the CosmicWorks catalog with searchable text and embeddings, run BM25 and VectorDistance queries against one container, and refresh a stale embedding from the change feed.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you build both retrieval methods on one Azure Cosmos DB for NoSQL container. You load the CosmicWorks product catalog with a searchable text property and an embedding for every product, run BM25 keyword queries against a full-text index, run similarity queries with `VectorDistance`, and then use the change feed to refresh an embedding after the product it describes is renamed.

The container you work with already carries a full-text policy, a vector policy, and both indexes. The setup script configures these settings before you load data. What the container doesn't carry is data. Building the text that gets indexed and calling the model that produces the vectors are application decisions, and they're the decisions this exercise is about.

This exercise takes approximately **45** minutes to complete.

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

1. Sign in to the Azure CLI. Follow the sign-in prompt. On Windows, the Azure CLI uses Web Account Manager by default. On Linux and macOS, it uses browser-based sign-in by default.

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

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab16a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name**, **Account endpoint**, **Foundry account**, and **OpenAI endpoint** values the script prints. The Cosmos DB endpoint looks like `https://<your-account-name>.documents.azure.com:443/`. The script also saves the Foundry values in `logs/foundry-<account-name>.json`.

1. Set the account name the script printed, then open that account in the [Azure portal](https://portal.azure.com).

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Under **Settings**, select **Features**. Confirm **Vector Search for NoSQL API** is enabled, then enable **Full Text & Hybrid Search for NoSQL API**. Allow up to 15 minutes for enrollment and confirm both features are enabled before continuing. If either feature is unavailable, stop and resolve that prerequisite before creating containers.

1. Resume setup against this same account. The `-SearchFeaturesReady` compatibility switch requires an existing account name. It doesn't verify your portal check, and setup can enable missing vector-search account capabilities.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -AccountName $accountName -LabProfile search -SearchFeaturesReady -EnableFoundry -EmbeddingOnly -FoundryLocation $location
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile search -EnableFoundry -EmbeddingOnly
    ```

    Continue only after setup and verification succeed. If enrollment is still propagating, rerun against the same account after it completes.

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

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Azure operations use Microsoft Entra ID authentication, which is the recommended approach for new accounts. The application code uses `DefaultAzureCredential`, which can select another configured identity before your Azure CLI identity. Confirm that the selected identity has the required roles.

> [!WARNING]
> Use only the resource group and account this script creates. Vector indexing and search can't be disabled on a container after enablement, and vector policy settings can't be edited directly. Never point this exercise at a shared training or production account.

1. Set variables for the account name and its endpoint so later commands can use them.

    ```powershell
    $accountName = "<your-account-name>"
    $cosmosEndpoint = "https://$accountName.documents.azure.com:443/"
    ```

## Task 1: Confirm the embedding deployment

Setup deploys the embedding model through `foundry.bicep` and grants your identity access. The `-EmbeddingOnly` switch avoids creating a chat deployment that this exercise doesn't use.

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

> [!NOTE]
> If setup fails because of model availability or quota, resolve the issue and rerun against the same Cosmos DB account. Use `-FoundryLocation` and, for a different Foundry resource, `-FoundryAccountName` consistently on both setup stages. A new role assignment can take several minutes to propagate before inference succeeds.

## Task 2: Load the catalog with searchable text and embeddings

The container's full-text index covers `/searchText` and its vector index covers `/embedding`, and neither property exists in the CosmicWorks data. In this task, you build both as you load the catalog.

The searchable text matters more than it sounds. The CosmicWorks `description` property holds a generated sentence of the form `The product called "<name>"` for all 295 products, so it repeats the same boilerplate around each product's distinct name. The product name and its category carry the words a shopper types, so this exercise concatenates those two into `searchText` and embeds the same string.

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


    with urllib.request.urlopen(DATA_URL) as response:
        products = json.load(response)

    print(f"Downloaded {len(products)} products.")

    for start in range(0, len(products), 50):
        batch = products[start:start + 50]
        texts = [build_search_text(product) for product in batch]

        embeddings = openai_client.embeddings.create(input=texts, model=DEPLOYMENT)

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

The catalog is loaded, and every item now carries the text the full-text index reads, the vector the similarity search ranks, and the hash that task 5 uses to decide whether either needs regenerating.

## Task 3: Search the catalog with BM25 ranking

In this task, you run the three kinds of full-text query against the data you loaded and confirm each returns what the catalog contains.

1. In the [Azure portal](https://portal.azure.com), open your Azure Cosmos DB account, select **Data Explorer**, expand the `cosmicworks` database and the `productSearch` container, and select **Items**.

1. Select **New SQL Query** and run the following query, which finds every item whose searchable text contains the term.

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

    The count jumps to roughly 90: every mountain bike, mountain frame, and mountain accessory, plus the three helmets. The exact number depends on how the analyzer tokenizes each name, so record what yours returns.

1. Rank results by relevance instead of filtering them.

    ```sql
    SELECT TOP 10 c.name, c.categoryName
    FROM c
    ORDER BY RANK FullTextScore(c.searchText, "mountain", "frame")
    ```

    Items that carry both terms sort above items that carry one. Now add `FullTextScore(c.searchText, "mountain", "frame") AS score` to the `SELECT` list and run the query again. It fails, because the score can appear only in an `ORDER BY RANK` clause.

1. Compare the cost of the index against a substring scan. Run each of the following queries, and after each one open the **Query Stats** tab and record the **Request Charge**.

    ```sql
    SELECT VALUE COUNT(1) FROM c WHERE FullTextContains(c.searchText, "helmet")
    ```

    ```sql
    SELECT VALUE COUNT(1) FROM c WHERE CONTAINS(c.searchText, "Helmet")
    ```

    At 295 items both queries are cheap, and the gap between them is small. The published comparison on a production-sized container is not small: 3.11 RUs for `FullTextContains` against 12,614 RUs for `CONTAINS`. The reason is visible in the two queries you just ran. One reads a prepared index; the other reads every item.

## Task 4: Search the catalog by meaning

In this task, you run a similarity query whose search terms appear nowhere in the catalog.

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

    response = openai_client.embeddings.create(input=search_text, model=DEPLOYMENT)
    query_vector = response.data[0].embedding

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

The search phrase contains none of the words *helmet*, *Sport-100*, or *Accessories*, so the query that returned three results in task 3 returns nothing for this text. The similarity query ranks the whole catalog by meaning instead, and the helmets are the products whose meaning is closest. Record the five names and scores your run returns. With only 295 vectors, this query uses a full scan rather than the approximate index.

1. Add a metadata filter and compare the request charge. Replace the query in your application with the following code, and set the parameter to the helmet category identifier `14A1AD5D-59EA-4B63-A189-67B077783B0E`.

    ```sql
    SELECT TOP 5 c.name, c.price,
        VectorDistance(c.embedding, @queryVector) AS similarityScore
    FROM c
    WHERE c.categoryId = @categoryId
    ORDER BY VectorDistance(c.embedding, @queryVector)
    ```

    The equality filter targets one logical partition and routes to its physical partition. It can reduce the request charge, but a small container can already occupy one physical partition, so a reduction isn't guaranteed.

> [!NOTE]
> This container holds 295 vectors, and `diskANN` needs at least 1,000 before its index takes effect. Every similarity query you just ran used a full scan. The queries still rank the stored vectors, but these request charges don't predict the cost of searching a larger, indexed container. Treat the numbers as a comparison between the two queries you ran rather than as a figure to plan capacity from.

## Task 5: Refresh an embedding from the change feed

Renaming a product doesn't update its stored `searchText` or embedding. The full-text index updates when the application writes a new `searchText` value. In this task, you rename a product, then run a change feed consumer that finds the mismatch and repairs it.

1. In the portal **Data Explorer**, run the following query and record the identifier and category of the first result.

    ```sql
    SELECT c.id, c.categoryId, c.name, c.searchText
    FROM c
    WHERE c.name = "Sport-100 Helmet, Red"
    ```

1. Select the item in the **Items** list, change its `name` to `Sport-100 Head Protector, Red`, and select **Update**.

1. Confirm the mismatch. Run the previous query again with the new name and compare `name` against `searchText`. The name changed, and the searchable text and the vector still describe the old one.

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

    for page in container.query_items_change_feed(start_time="Beginning").by_page():
        for change in page:
            scanned += 1
            text = build_search_text(change)

            if content_hash(text) == change.get("contentHash"):
                continue

            response = openai_client.embeddings.create(input=text, model=DEPLOYMENT)

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

Latest-version mode returns the latest available version of each changed item when the feed is read, not a history of every write. The rename replaces the version the load wrote. Writes made while the consumer runs can appear in later pages, including the embedding refresh itself, so the scanned count can exceed 295. Only the renamed product needs an embedding refresh in this exercise.

1. Run the consumer a second time without changing anything.

    ```output
    Scanned 295 changes, refreshed 0.
    ```

    The consumer reads the same 295 products, and this time every hash matches the text, so nothing is refreshed. The refresh in the previous run was itself a write. That write can appear in the same run or in a later read, depending on when the consumer reads the feed. A continuation token resumes from the last read position. Without the hash guard, the consumer would re-embed its own output on every pass and never stop.

1. Confirm the repair in the portal. Run the query from the start of this task with `WHERE c.name = "Sport-100 Head Protector, Red"` and check that `searchText` now carries the new name.

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

Deleting the group removes the account, the AI Services resource, and the deployment together. The role assignment you created is scoped to the AI Services resource, so it goes with it.

Two retrieval methods now run against one container, over one copy of the data, under one set of permissions. The full-text index maintains itself as items change, and the vectors need a refresh path you own, which is the operational difference worth carrying out of this exercise.
