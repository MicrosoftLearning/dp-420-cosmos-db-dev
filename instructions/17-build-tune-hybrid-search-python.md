---
lab:
  title: Build and Tune Hybrid Search in Python
  module: Module 17 - Implement Hybrid Search and Optimize AI Retrieval in Azure Cosmos DB for NoSQL
  description: Load a catalog with searchable text and embeddings, measure keyword and semantic retrieval separately, fuse them with RRF, weight the fusion, and optimize the query against measured request charges.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Build and Tune Hybrid Search in Python

In this exercise, you build a hybrid retrieval pipeline on one Azure Cosmos DB for NoSQL container and tune it with measurements rather than impressions. You load the CosmicWorks product catalog with a searchable text property and an embedding for every product, run the keyword and semantic halves separately so you can see what each one misses, fuse them with `RRF`, bias the fusion with weights, and then measure what each optimization does to the request charge.

The catalog is chosen to make both failure modes visible. No product name or category name in the 295 products contains the word *see* or the word *night*, while 96 of them contain the word *road*, so a keyword query for *something to see the road at night* has exactly one usable term and it points away from the answer. The catalog also holds four size variants of the same touring bike, differing by two characters and priced identically, so a semantic query for one of them has almost nothing to separate them by.

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

1. Sign in to the Azure CLI. Follow the sign-in prompt, which uses an account picker on supported Windows systems or a browser on other systems.

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

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab17a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name**, **Account endpoint**, **Foundry account**, and **OpenAI endpoint** values the script prints. The Cosmos DB endpoint looks like `https://<your-account-name>.documents.azure.com:443/`. The script also saves the Foundry values in `logs/foundry-<account-name>.json`.

1. Set the account name the script printed, then open that account in the [Azure portal](https://portal.azure.com).

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Under **Settings**, select **Features**. Confirm **Vector Search for NoSQL API** is enabled. Allow up to 15 minutes for vector search activation before creating containers. Full-text search uses the container's full-text policy and index and doesn't require a separate enrollment step for this exercise.

1. Resume setup against this same account to create the database, container, and Cosmos DB role assignment.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -AccountName $accountName -LabProfile search -SearchFeaturesReady -EnableFoundry -EmbeddingOnly -FoundryLocation $location
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile search -EnableFoundry -EmbeddingOnly
    ```

    Continue only after setup and verification succeed. If vector search activation is still propagating, rerun against the same account after it completes.

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

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The setup script uses your Azure CLI identity. The application uses `DefaultAzureCredential`, which can select another configured identity before trying Azure CLI. Make sure the selected identity has the required role assignments. Microsoft Entra ID authentication is the recommended approach for new accounts.

> &#9888; Use only the resource group and account this script creates. Vector search is an account capability that can't be turned off once it's enabled, and the container's vector policy settings can't be edited in place. Never point this exercise at a shared training or production account.

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

> &#128221; If setup fails because of model availability or quota, resolve the issue and rerun against the same Cosmos DB account. Use `-FoundryLocation` and, for a different Foundry resource, `-FoundryAccountName` consistently on both setup stages. For a custom Foundry account name, also pass `-FoundryAccountName` to `verify.ps1`. A new role assignment can take several minutes to propagate before inference succeeds.

## Task 2: Load the catalog with searchable text and embeddings

The container's full-text index covers `/searchText` and its vector index covers `/embedding`, and neither property exists in the CosmicWorks data. In this task, you build both as you load the catalog.

What goes into `searchText` decides what the keyword half can ever find. The CosmicWorks `description` property holds a generated sentence of the form `The product called "<name>"` for all 295 products, with no exceptions. Each description includes a different product name but adds no explanation of the product's purpose. The product name and its category carry the words a shopper types, so this exercise concatenates those two and embeds the same string.

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
    pip install azure-cosmos azure-identity openai
    ```

1. Create a file named **load.py** and add the following code. Replace the two placeholder values with your endpoints.

    ```python
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

    with urllib.request.urlopen(DATA_URL) as response:
        products = json.load(response)

    print(f"Downloaded {len(products)} products.")

    for start in range(0, len(products), 50):
        batch = products[start:start + 50]
        texts = [f"{product['name']} {product['categoryName']}" for product in batch]

        embeddings = openai_client.embeddings.create(input=texts, model=DEPLOYMENT)

        for product, text, data in zip(batch, texts, embeddings.data):
            product["searchText"] = text
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

Every item now carries the text the full-text index reads and the vector the similarity search ranks, so both halves of a hybrid query have something to work with.

## Task 3: Measure each retrieval method on its own

Before fusing anything, run the two halves separately so you can see what each one contributes. In this task, you run a keyword query and a similarity query for the same shopper phrase and record what each returns and what each costs.

The phrase is *something to see the road at night*. Its content words are *see*, *road*, and *night*, and only one of them appears anywhere in the catalog's searchable text.

1. Create a file named **compare.py** and add the following code, replacing the two placeholder values with your endpoints.

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

    SEARCH_TEXT = "something to see the road at night"
    TERMS = ["see", "road", "night"]


    def embed(text):
        return openai_client.embeddings.create(input=text, model=DEPLOYMENT).data[0].embedding


    def run(label, query, parameters):
        request_charges = []

        def record_charge(headers, response):
            request_charges.append(float(headers.get("x-ms-request-charge", 0)))

        results = list(container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True,
            response_hook=record_charge,
        ))
        charge = sum(request_charges)
        print(f"\n{label}  ({charge} RUs)")
        for item in results:
            print(f"  {item['name']}  |  {item['categoryName']}")


    keyword_query = """
        SELECT TOP 5 c.name, c.categoryName
        FROM c
        ORDER BY RANK FullTextScore(c.searchText, @term1, @term2, @term3)
    """

    vector_query = """
        SELECT TOP 5 c.name, c.categoryName
        FROM c
        ORDER BY RANK VectorDistance(c.embedding, @queryVector)
    """

    run("Keyword only", keyword_query, [
        {"name": "@term1", "value": TERMS[0]},
        {"name": "@term2", "value": TERMS[1]},
        {"name": "@term3", "value": TERMS[2]},
    ])

    run("Vector only", vector_query, [
        {"name": "@queryVector", "value": embed(SEARCH_TEXT)},
    ])
    ```

1. Run the application.

    ```powershell
    python compare.py
    ```

1. Compare the two result lists and record them. The catalog holds exactly three items in the *Accessories, Lights* category, and those three are what the shopper is asking for.

    The corpus, not the ranking, constrains the keyword result. The words *see* and *night* appear in no product name or category in the catalog, so the only term BM25 can score on is *road*, which 96 items carry. The similarity result reads the phrase as a description of purpose.

    Record which list contains any of the three lights, and the request charge each query reported. Ranking depends on your data and model deployment. Approximate indexing can also affect ranking when the index is active, but this catalog is below the threshold explained in task 6. Write down what your queries return rather than matching them to an expected list.

1. Now change the shopper phrase. Change `SEARCH_TEXT` to `Touring-1000 Blue, 50` and the three terms to `Touring`, `1000`, and `Blue`, and run the application again.

    The catalog holds four size variants of that model, all priced identically and differing by two characters. The keyword terms match the model and color but omit the requested size, so they don't distinguish the four variants by size. Similarity scoring compares four almost identical strings. Record the order from each method without assuming either one ranks the requested size first.

## Task 4: Fuse the two rankings with RRF

You now have results from both retrieval methods. In this task, you run both in one query and let `RRF` combine the rankings.

1. Add the following query and call to the end of your application, before you rerun it. Restore `SEARCH_TEXT` to `something to see the road at night` and the terms to `see`, `road`, and `night` first.

    ```python
    hybrid_query = """
        SELECT TOP 5 c.name, c.categoryName
        FROM c
        ORDER BY RANK RRF(
            VectorDistance(c.embedding, @queryVector),
            FullTextScore(c.searchText, @term1, @term2, @term3))
    """

    run("Hybrid", hybrid_query, [
        {"name": "@queryVector", "value": embed(SEARCH_TEXT)},
        {"name": "@term1", "value": TERMS[0]},
        {"name": "@term2", "value": TERMS[1]},
        {"name": "@term3", "value": TERMS[2]},
    ])
    ```

1. Run the application and compare all three lists.

    The fused list draws from both rankings, so items that only one method found can appear alongside items that both found. Record how many of the five results came from each of the earlier lists, and record the hybrid query's request charge next to the other two.

1. Confirm one of the rules that governs where `RRF` can appear. Add `, c.price` to the projection and run again, which works. Then try to project the fused score itself by adding `RRF(...) AS score` to the `SELECT` list.

    The query fails because `RRF` can't appear in the projection. `FullTextScore` also can't be projected or used in a `WHERE` clause. You can project `VectorDistance` separately, but its value isn't the fused score. Remove the invalid `RRF` projection before continuing.

## Task 5: Weight the fusion and compare the results

An unweighted fusion treats both rankings as equally credible. In this task, you bias it in each direction and watch the result list move.

1. Change the hybrid query to weight the vector half twice as heavily as the keyword half, by adding a weights array as the last argument to `RRF`.

    ```sql
    ORDER BY RANK RRF(
        VectorDistance(c.embedding, @queryVector),
        FullTextScore(c.searchText, @term1, @term2, @term3),
        [2, 1])
    ```

1. Run the application and record the result list.

1. Change the weights to `[1, 2]` and run it again.

    The weights correspond to the functions positionally, so `[2, 1]` favors the function listed first and `[1, 2]` favors the second. Record how the list changes between the two runs.

1. Now introduce the mistake the positional rule invites. Swap the order of the two functions inside `RRF` while leaving the weights at `[1, 2]`, and run it once more.

    ```sql
    ORDER BY RANK RRF(
        FullTextScore(c.searchText, @term1, @term2, @term3),
        VectorDistance(c.embedding, @queryVector),
        [1, 2])
    ```

    The query runs and now favors vector search instead of keyword search. Swapping the functions doesn't cause an error, which is why the function order and the weights array get reviewed together.

## Task 6: Optimize the hybrid query and measure the difference

In this task, you apply the cheapest optimizations in order and record what each one does to the request charge.

> &#128221; The container holds 295 vectors, and the `diskANN` index takes effect only once at least 1,000 vectors are indexed. Every similarity and hybrid query in this exercise runs a full scan instead, so the results are correct and the request charges are not representative of production. Read the numbers as a comparison between two queries in the same container rather than as a capacity figure.

1. Restore the unweighted `TOP 5` hybrid query from task 4, with the original shopper phrase and terms. Run it and record its request charge as your baseline.

1. Reduce the result count. Change `TOP 5` to `TOP 3` in the hybrid query, run the application, and record the charge.

1. Add a partition key filter. The three lights all sit in one category, so filtering to it routes the query to a single logical partition.

    ```python
    filtered_query = """
        SELECT TOP 3 c.name, c.categoryName
        FROM c
        WHERE c.categoryId = @categoryId
        ORDER BY RANK RRF(
            VectorDistance(c.embedding, @queryVector),
            FullTextScore(c.searchText, @term1, @term2, @term3))
    """

    run("Hybrid, filtered", filtered_query, [
        {"name": "@categoryId", "value": "11EF8851-816A-49E2-9D5C-8D17AB82C5FF"},
        {"name": "@queryVector", "value": embed(SEARCH_TEXT)},
        {"name": "@term1", "value": TERMS[0]},
        {"name": "@term2", "value": TERMS[1]},
        {"name": "@term3", "value": TERMS[2]},
    ])
    ```

1. Run the application and record the charge.

    The filter narrows the ranked set to one category. Use your measurements to determine its effect on request charge rather than assuming it produces the largest saving. It returns lights and nothing else, so it works only when the application already knows the category, and it's the wrong tool when the category is what the shopper is trying to discover.

1. Establish a ground truth for the semantic half. Run a similarity query with the third argument to `VectorDistance` set to `true`, which forces an exhaustive comparison against every stored vector.

    ```sql
    SELECT TOP 5 c.name, c.categoryName
    FROM c
    ORDER BY VectorDistance(c.embedding, @queryVector, true)
    ```

1. Compare that list against the unfiltered `TOP 5` similarity results from task 3 for the same shopper phrase and query vector, and record the request charge next to the others.

    At this container's size, both queries scan rather than use the `diskANN` index. Compare their top-five results, allowing for ties, and measure their charges instead of assuming the charges are close. On a container with an active `diskANN` index and at least 1,000 indexed vectors, comparing the same number of results against brute force measures the approximate query's recall.

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

You now have a row of request charges beside a row of result lists for the same shopper phrase. That pairing is what turns retrieval tuning into a decision the product can make, because every change you tried has both a relevance consequence and a cost consequence, and neither one is visible without the other.
