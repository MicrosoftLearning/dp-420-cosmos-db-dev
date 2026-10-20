---
lab:
  title: Process changes and copy data in Python
  module: Module 7 - Process the Azure Cosmos DB for NoSQL Change Feed
  description: Synchronize product category names with the change feed, log updates with an Azure Functions trigger, and copy a container to a new partition key.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Process changes and copy data in Python

In this exercise, you use the change feed to keep product category names in sync, log product updates with an Azure Function, and copy products to a container with a different partition key.

Products store a copy of the category name from `productMeta`. A category rename updates the metadata document; the consumer updates the corresponding products.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

This exercise also requires:

- [Azure Functions Core Tools](/azure/azure-functions/functions-run-local) version 4.
- [Azurite](/azure/storage/common/storage-use-azurite), for the function's local storage.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab07 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab07a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds every container this learning path uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 category and tag records |
| `leases` container | Partitioned on `/id`, 400 RU/s. The change feed processor stores its checkpoints here |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

> &#10071; Container copy jobs in Task 4 run in the account's write region and are available in a subset of Azure regions. The setup script warns you if the region you chose doesn't support them. Check the [supported regions](/azure/cosmos-db/container-copy) if you need to pick a different one.

## Task 1: Set up the project and confirm the catalog

Use the account endpoint recorded during setup wherever the code contains `<cosmos-endpoint>`.

Create a project and install the required packages:

```powershell
mkdir change-feed-lab
cd change-feed-lab
python -m venv .venv
.venv\Scripts\activate
pip install azure-cosmos azure-identity
```

Create `check_catalog.py` in the `change-feed-lab` directory:

```python
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

endpoint = "<cosmos-endpoint>"

# Use a developer credential, such as az login, instead of an account key.
client = CosmosClient(endpoint, credential=DefaultAzureCredential())
database = client.get_database_client("cosmicworks")

for name in ["productMeta", "product"]:
    container = database.get_container_client(name)
    # SELECT VALUE returns a scalar count across the container, not item documents.
    count = list(
        container.query_items(
            query="SELECT VALUE COUNT(1) FROM c",
            enable_cross_partition_query=True,
        )
    )[0]

    print(f"{name}: {count} items")
```

Run it:

```bash
python check_catalog.py
```

```output
productMeta: 237 items
product: 295 items
```

The `type` property distinguishes category documents from tag documents in `productMeta`.

## Task 2: Sync a denormalized property from the change feed

Build a consumer that watches `productMeta` and rewrites `categoryName` on every product in a renamed category.

The Python SDK doesn't include the change feed processor, so this consumer reads the feed directly and keeps its own position.

Create `sync.py` in the `change-feed-lab` directory:

```python
import time

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

endpoint = "<cosmos-endpoint>"

client = CosmosClient(endpoint, credential=DefaultAzureCredential())
database = client.get_database_client("cosmicworks")
# Watch metadata, then update the denormalized categoryName in a different container.
monitored = database.get_container_client("productMeta")
products = database.get_container_client("product")

# This bookmark exists only in memory; restarting the script doesn't reload it.
continuation = None
print("Reading the change feed. Press Ctrl+C to stop.")

while True:
    if continuation:
        changes = monitored.query_items_change_feed(continuation=continuation)
    else:
        # Start with future changes, not a replay of the existing metadata catalog.
        changes = monitored.query_items_change_feed(start_time="Now")

    for item in changes:
        # productMeta mixes category and tag documents; only categories drive this sync.
        if item.get("type") != "category":
            continue

        updated = 0
        # The category document's id is the product container's partition key value.
        results = products.query_items(
            query="SELECT p.id, p.categoryId FROM product p WHERE p.categoryId = @categoryId",
            parameters=[{"name": "@categoryId", "value": item["id"]}],
            partition_key=item["id"],
        )

        for product in results:
            # Setting the absolute name makes replay of this update safe;
            # the product writes aren't one cross-container transaction.
            products.patch_item(
                item=product["id"],
                partition_key=product["categoryId"],
                patch_operations=[
                    {"op": "set", "path": "/categoryName", "value": item["name"]}
                ],
            )
            updated += 1

        print(f"Category '{item['name']}' synced to {updated} products.")

    continuation = monitored.client_connection.last_response_headers["etag"]
    time.sleep(5)
```

Run it:

```bash
python sync.py
```

```output
Reading the change feed. Press Ctrl+C to stop.
```

Leave this terminal open with the consumer running while you perform the next steps.

With the consumer running, rename a category from a second terminal. Category `3E4CEACD-D007-46EB-82D7-31F6141752B2` is *Components, Road Frames*, and its partition key value is `category`.

Create `rename.py` in the `change-feed-lab` directory, alongside `sync.py`:

```python
from datetime import datetime, timezone

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

endpoint = "<cosmos-endpoint>"
category_id = "3E4CEACD-D007-46EB-82D7-31F6141752B2"

client = CosmosClient(endpoint, credential=DefaultAzureCredential())
container = client.get_database_client("cosmicworks").get_container_client("productMeta")

stamp = datetime.now(timezone.utc).strftime("%H%M%S")
# Change the value on each run so the consumer has a new update to observe.
new_name = f"Components, Road Frames (revised {stamp})"

# This metadata container uses /type: the partition key is "category", not the GUID.
container.patch_item(
    item=category_id,
    partition_key="category",
    patch_operations=[{"op": "set", "path": "/name", "value": new_name}],
)

print(f"Renamed category to '{new_name}'.")
```

Open a second terminal in the `change-feed-lab` folder and run the rename there. The virtual environment belongs to the first terminal, so activate it again:

```powershell
.venv\Scripts\activate
python rename.py
```

Keep the consumer running in its original terminal.

Switch back to the consumer's terminal. It reports the new category name and the number of products it patched. Run the rename a second time to watch the consumer pick up another change.

Review the consumer's behavior:

- **Metadata filtering:** The feed contains category and tag documents. Only category changes require updates to the products.
- **Start position:** On its first run, the consumer starts with future changes.

> &#10071; This Python consumer keeps its continuation token in memory. Restarting it starts from `Now`, so changes made while it was stopped aren't processed. A production consumer must persist its token after successful processing and reload it on restart.

## Task 3: React to changes with an Azure Function

Use an Azure Functions trigger to log changes to `product`. The Task 2 consumer's product updates trigger the function.

Open a new integrated terminal in the Shared folder.

```bash
func init product-audit --worker-runtime python --model V2
cd product-audit
```

Replace `function_app.py` with:

```python
import logging

import azure.functions as func

app = func.FunctionApp()


@app.function_name(name="ProductAudit")
# The binding resolves %...% from host settings and uses leases for feed progress.
@app.cosmos_db_trigger(
    arg_name="changes",
    database_name="%COSMOS_DATABASE_NAME%",
    container_name="%COSMOS_CONTAINER_NAME%",
    connection="COSMOS_CONNECTION",
    lease_container_name="leases",
)
def product_audit(changes: func.DocumentList) -> None:
    # Log each product in the change feed batch.
    for product in changes:
        logging.info(
            "Product %s is now in category '%s'.",
            product["id"],
            product.get("categoryName"),
        )
```

Set `local.settings.json`:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "COSMOS_DATABASE_NAME": "cosmicworks",
    "COSMOS_CONTAINER_NAME": "product",
    "COSMOS_CONNECTION__accountEndpoint": "<cosmos-endpoint>"
  }
}
```

Azurite provides local storage for the Functions host. The catalog remains in Azure Cosmos DB, and the function's change feed checkpoints are stored in `leases`.

Start Azurite in this terminal (this application can take a few moments to initialize):

```bash
azurite --silent
```

Start the function in a new terminal on this folder:

```bash
func start
```

> &#128221; Select **Allow** if the function requests network access.


The function uses your Azure CLI sign-in and the existing `leases` container.

Test the pipeline:

1. Go to the terminal you used for the rename program and run it again.

1. Watch the Task 2 consumer. It reports the category it synced and how many products it patched.

1. Watch the `func start` terminal for product update messages:

    ```output
    Product 0AE1D2B4-... is now in category 'Components, Road Frames (revised 051233)'.
    ```

## Task 4: Copy a container onto a new partition key

Create a destination container with the new partition key and copy the source data into it.

> &#128221; Container copy jobs are in preview. The jobs run on a best-effort basis with no service-level agreement.

Stop the consumer, function, and Azurite, then close their terminals. Don't write to the source container while the offline copy job runs.

The rest of this task runs in the Azure CLI. In the **Explorer** pane, open the context menu for the **Allfiles/Labs/Shared** folder and select **Open in Integrated Terminal**, then sign in:

```azurecli
az login
```

Set the variables in this new terminal. Use your lab's resource group name and the account name recorded during setup:

```powershell
$resourceGroup = "ResourceGroup1"
$accountName = "<your-account-name>"
```

Create the destination container with the new key:

```azurecli
az cosmosdb sql container create `
    --account-name $accountName `
    --resource-group $resourceGroup `
    --database-name cosmicworks `
    --name productArchive `
    --partition-key-path "/id" `
    --throughput 800
```

Install the preview extension for the copy commands:

```azurecli
az extension add --name cosmosdb-preview
```

Create the copy job:

```azurecli
az cosmosdb copy create `
    --resource-group $resourceGroup `
    --job-name product-to-archive `
    --src-account $accountName `
    --dest-account $accountName `
    --src-nosql database=cosmicworks container=product `
    --dest-nosql database=cosmicworks container=productArchive
```

The command creates an asynchronous copy job. Monitor its progress with the following command until `status` is `Completed`:

```azurecli
az cosmosdb copy show `
    --resource-group $resourceGroup `
    --account-name $accountName `
    --job-name product-to-archive
```

```output
"duration": "00:00:05.4670000",
"processedCount": 295,
"status": "Completed",
"totalCount": 295,
```

The copy job reads the source container's change feed. A completed job should report 295 for both `totalCount` and `processedCount`.

Confirm the copy in the Azure portal: open **Data Explorer**, select the `productArchive` container, and run `SELECT VALUE COUNT(1) FROM c`. It returns 295, the same count `product` holds.

The copied items retain their original `id` values. The destination container partitions on `/id` instead of `/categoryId`.

For other migrations, make sure the combination of `id` and the new partition key value remains unique within the container.

## Clean up resources

When you finish the course, delete the resource group only if you created it and every resource in it can be removed. If your lab provided `ResourceGroup1`, skip this command and delete only the exercise resources you no longer need:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

The `leases` and `productArchive` containers consume provisioned throughput for as long as they exist, so leaving them in place has a running cost.
