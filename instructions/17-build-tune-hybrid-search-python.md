---
lab:
  title: Build and Tune Hybrid Search in Python
  module: Module 17 - Implement Hybrid Search and Optimize AI Retrieval in Azure Cosmos DB for NoSQL
  description: Compare keyword, vector, and RRF retrieval, adjust fusion weights, and measure relevance, request charge, and latency.
  duration: 60 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Build and Tune Hybrid Search in Python

In this exercise, you build hybrid search over the CosmicWorks product catalog in Azure Cosmos DB for NoSQL. You compare keyword and vector results, combine them with `RRF`, and adjust the weights while measuring request charge and latency.

This exercise takes approximately **60** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

The setup script creates a Microsoft Foundry resource, project, and `text-embedding-3-small` deployment. Your subscription needs quota for that model in the Foundry region.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab17 -LabProfile search -AccountOnly -EnableFoundry -EmbeddingOnly -FoundryLocation $location
    ```

    The script generates a unique account name, such as `dp420lab17a7f3k9`.

1. Wait for the script to finish. This takes 5-10 minutes.

1. Record the **Account name**, **Account endpoint**, **Foundry account**, and **OpenAI endpoint** values the script prints. The Cosmos DB endpoint looks like `https://<your-account-name>.documents.azure.com:443/`. The script also saves the Foundry values in `logs/foundry-<account-name>.json`.

1. Set the account name the script printed, then open that account in the [Azure portal](https://portal.azure.com).

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Under **Settings**, select **Features**. Confirm **Vector Search for NoSQL API** is enabled. Allow up to 15 minutes for activation before creating containers.

1. Resume setup against this same account to create the database, container, and Cosmos DB role assignment.

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

The applications use `DefaultAzureCredential` for Microsoft Entra ID authentication. Make sure the identity it selects has the role assignments listed above.

> &#9888; Use the dedicated account created for this exercise, not a shared training or production account.

1. Set variables for the account name and its endpoint so later commands can use them.

    ```powershell
    $accountName = "<your-account-name>"
    $cosmosEndpoint = "https://$accountName.documents.azure.com:443/"
    ```

## Task 1: Confirm the embedding deployment

Confirm that the embedding deployment is ready before loading the catalog.

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

The catalog descriptions repeat the product names. This exercise combines each name and category into `searchText` and embeds that same text. The container's indexes read `/searchText` and `/embedding`.

1. Create a folder for the application and open it in the integrated terminal.

    ```powershell
    mkdir hybrid-lab
    cd hybrid-lab
    ```

1. Create and activate a virtual environment.

    ```powershell
    python -m venv .venv
    .venv\Scripts\activate
    ```

    On Linux or macOS, activate the environment with `source .venv/bin/activate`.

1. Install the packages the exercise uses.

    ```powershell
    python -m pip install azure-cosmos azure-identity openai truststore
    ```

    The `truststore` package validates the catalog download using the operating system's trusted certificates.

1. Create a file named **load.py** and add the following code. Replace the two placeholder values with your endpoints.

    ```python
    import json
    import ssl
    import urllib.request

    import truststore
    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    COSMOS_ENDPOINT = "<cosmos-endpoint>"
    OPENAI_ENDPOINT = "<openai-endpoint>"
    DEPLOYMENT = "text-embedding-3-small"
    DATA_URL = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product"

    # Reuse a credential for both services. Azure OpenAI receives a token
    # scoped to Cognitive Services, while Cosmos DB handles its own audience.
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

    # Validate the download with the operating system's trusted certificates.
    ssl_context = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    with urllib.request.urlopen(DATA_URL, context=ssl_context) as response:
        products = json.load(response)

    print(f"Downloaded {len(products)} products.")

    # Use the same name-and-category text for both search methods.
    for start in range(0, len(products), 50):
        batch = products[start:start + 50]
        texts = [f"{product['name']} {product['categoryName']}" for product in batch]

        embeddings = openai_client.embeddings.create(input=texts, model=DEPLOYMENT)

        # Pair each vector with its source product; each upsert is a separate write.
        for product, text, data in zip(batch, texts, embeddings.data):
            product["searchText"] = text
            product["embedding"] = data.embedding
            # Preserve the ID and partition key so reruns replace the same logical item.
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

## Task 3: Measure each retrieval method on its own

Compare keyword and vector results for these two shopper requests.

| Case | Shopper query | Useful result criteria |
| :--- | :--- | :--- |
| Hill riding | `I need some tires to ride up the hill.` | Tires rather than complete bikes, pumps, or inner tubes. |
| Exact bike | `Touring-1000 Blue, 50` | The product must match the model, color, and size. Another size or color doesn't meet this request. |

Each query returns up to five products. Keyword search matches terms in `searchText`; vector search ranks by embedding similarity.

1. Create a file named **compare.py** and add the following code, replacing the two placeholder values with your endpoints.

    ```python
    from time import perf_counter

    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    # Edit each search phrase and its keyword terms together when testing scenarios.
    cases = [
        {
            "label": "Hill riding",
            "text": "I need some tires to ride up the hill.",
            "terms": ["tires", "ride", "hill"],
        },
        {
            "label": "Exact bike",
            "text": "Touring-1000 Blue, 50",
            "terms": ["Touring", "1000", "Blue", "50"],
        },
    ]

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


    def run(label, query, parameters):
        request_charges = []

        def record_charge(headers, response):
            # The hook runs per response; the final page alone isn't the total RU charge.
            request_charges.append(float(headers["x-ms-request-charge"]))

        # Query execution is lazy; consume every page before totaling charge and elapsed time.
        start = perf_counter()
        results = list(container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True,
            response_hook=record_charge,
        ))
        elapsed_ms = (perf_counter() - start) * 1000
        charge = sum(request_charges)
        print(f"\n{label}: {charge:.2f} RUs; {elapsed_ms:.1f} ms")
        for item in results:
            print(f"  {item['name']}  |  {item['categoryName']}")


    for case in cases:
        # Generate once per case and reuse across methods; time this model call separately.
        start = perf_counter()
        response = openai_client.embeddings.create(input=case["text"], model=DEPLOYMENT)
        embedding_ms = (perf_counter() - start) * 1000
        query_vector = response.data[0].embedding

        print(f"\n{case['label']}: {case['text']}")
        print(f"Query embedding: {embedding_ms:.1f} ms")

        # Bind term values as parameters; generate only the placeholder names.
        term_parameters = [
            {"name": f"@term{i}", "value": term}
            for i, term in enumerate(case["terms"])
        ]
        term_arguments = ", ".join(parameter["name"] for parameter in term_parameters)
        vector_parameters = [{"name": "@queryVector", "value": query_vector}]

        # Rank products that contain at least one search term.
        keyword_query = f"""
            SELECT TOP 5 c.id, c.name, c.categoryName
            FROM c
            WHERE FullTextContainsAny(c.searchText, {term_arguments})
            ORDER BY RANK FullTextScore(c.searchText, {term_arguments})
        """

        # Rank by meaning without requiring a keyword match.
        vector_query = """
            SELECT TOP 5 c.id, c.name, c.categoryName
            FROM c
            ORDER BY RANK VectorDistance(c.embedding, @queryVector)
        """

        run("Keyword only", keyword_query, term_parameters)
        run("Vector only", vector_query, vector_parameters)
    ```

1. Run the application.

    ```powershell
    python compare.py
    ```

1. Review the **Hill riding** results. In a sample run:

    - **Keyword only** mixes road, mountain, and touring tires. It found the requested product type by matching the word `tires`.
    - In **Vector only**, the three mountain-tire variants appear first even though the query never uses the word `mountain`.

    Both methods returned tires. Keyword search uses the indexed words; vector search also takes the hill-riding context into account.

1. Review the **Exact bike** results.

    Both methods place `Touring-1000 Blue, 50` first. An exact product name gives keyword search a strong match.

    The remaining keyword results include a yellow bike and a frame that share some terms. The remaining vector results are similar blue touring bikes, but include other sizes and the `Touring-2000` model. Similarity doesn't enforce an exact model or size requirement.

1. Review the cost and timing measurements.

    Vector search used **19.90 RU** for each case, compared with **7.98 RU** for the keyword hill-riding query and **14.06 RU** for the keyword exact-bike query in this run.

    The database **ms** excludes **Query embedding** time. The sample hill-riding query takes about **1.16 seconds** in Cosmos DB plus **8.8 seconds** to generate the embedding. Keyword search doesn't need that model call. Include both times when assessing response time.

    Timing can vary, especially on the first request while connections are established.

> &#128221; This catalog has 295 vectors, below the 1,000-vector threshold for `diskANN` indexing. Vector queries use a full scan, so these measurements don't represent indexed production performance.

## Task 4: Fuse the two rankings with RRF

Combine the word-based and meaning-based rankings in one query with `RRF`.

1. In `for case in cases:`, insert this code immediately after `run("Vector only", vector_query, vector_parameters)`, at the same indentation.

    ```python
    # Fuse rank positions, not raw scores.
    hybrid_query = f"""
        SELECT TOP 5 c.id, c.name, c.categoryName
        FROM c
        ORDER BY RANK RRF(
            VectorDistance(c.embedding, @queryVector),
            FullTextScore(c.searchText, {term_arguments}))
    """

    run("Hybrid, equal weights", hybrid_query,
        vector_parameters + term_parameters)
    ```

1. Run the application **once**. It prints all three lists for each case. In a sample run:

    - **Hill riding:** hybrid search keeps the mountain tires at the top, as vector search did. The road tires below them change order.
    - **Exact bike:** the requested bike stays first, followed by blue size variants of the same model. The yellow bike and frame don't appear, but other sizes still do.
    - **Cost:** hybrid search uses **47.77 RU** for hill riding and **52.28 RU** for the exact bike, more than either method alone. It keeps the same first result as vector search for both queries.

    `RRF` combines rank positions from keyword and vector search rather than adding their raw scores. The hybrid query reuses the existing query vector, so it doesn't make another embedding request.

## Task 5: Weight the fusion and compare the results

Change the balance between keyword and vector rankings with a weights array.

1. In `for case in cases:`, insert this code after the `Hybrid, equal weights` call, at the same indentation.

    ```python
    # The first weight applies to VectorDistance; the second applies to FullTextScore.
    for weights in ("[2, 1]", "[1, 2]"):
        weighted_query = f"""
            SELECT TOP 5 c.id, c.name, c.categoryName
            FROM c
            ORDER BY RANK RRF(
                VectorDistance(c.embedding, @queryVector),
                FullTextScore(c.searchText, {term_arguments}),
                {weights})
        """

        run(f"Hybrid {weights}", weighted_query,
            vector_parameters + term_parameters)
    ```

1. Run the application **once**. It prints the equal-weight and both weighted hybrid lists for each case. In a sample run:

    - **Hill riding:** equal weights and `[2, 1]` keep the mountain-tire variants together at the top. With `[1, 2]`, a road tire moves ahead of one of the mountain tires.
    - **Exact bike:** the requested bike stays first with all three settings. The vector-heavy setting moves a similar blue bike from another model higher. The keyword-heavy setting brings in a yellow bike that shares the requested model and size. More keyword weight doesn't require every term to match.
    - **Cost:** all three settings cost **47.77 RU** for hill riding and **52.28 RU** for the exact bike. Here, the weights change the order, not the RU charge. Timing varies between runs.

    Weights follow function order. With `VectorDistance` first and `FullTextScore` second, `[2, 1]` favors vector search and `[1, 2]` favors keyword search.

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
