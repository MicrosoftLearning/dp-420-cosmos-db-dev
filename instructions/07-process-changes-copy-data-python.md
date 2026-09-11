---
lab:
  title: Process changes and copy data in Python
  module: Module 7 - Process the Azure Cosmos DB for NoSQL Change Feed
  description: Run a change feed consumer against a lease container, react to changes with an Azure Functions trigger, and copy a container onto a new partition key with a copy job.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you build the pipeline described throughout this module. You load the CosmicWorks catalog and run a consumer. The consumer keeps the denormalized category name current. You then run the same logic in an Azure Function. Finally, you copy the data to a container that uses a different partition key.

The category name that products carry is a copy. Renaming a category in one container leaves that copy stale everywhere else until something reconciles it, and the change feed is what makes the reconciliation possible without polling.

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

The setup script created the `product`, `productMeta`, and `leases` containers, granted your identity data-plane access, and loaded the catalog. This task builds the project the rest of the exercise uses and confirms the data arrived.

Create a project and add the packages (remember to replace `<your-account-name>` and `<cosmos-endpoint>` with your actual values):

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

client = CosmosClient(endpoint, credential=DefaultAzureCredential())
database = client.get_database_client("cosmicworks")

for name in ["productMeta", "product"]:
    container = database.get_container_client(name)
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

`productMeta` holds two kinds of document discriminated by a `type` property: category documents and tag documents. That detail matters in the next task.

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
monitored = database.get_container_client("productMeta")
products = database.get_container_client("product")

continuation = None
print("Reading the change feed. Press Ctrl+C to stop.")

while True:
    if continuation:
        changes = monitored.query_items_change_feed(continuation=continuation)
    else:
        changes = monitored.query_items_change_feed(start_time="Now")

    for item in changes:
        if item.get("type") != "category":
            continue

        updated = 0
        results = products.query_items(
            query="SELECT p.id, p.categoryId FROM product p WHERE p.categoryId = @categoryId",
            parameters=[{"name": "@categoryId", "value": item["id"]}],
            partition_key=item["id"],
        )

        for product in results:
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

Leave this terminal open and the consumer running. The loop checks the feed every five seconds until you stop it, and the next step depends on it still running.

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
new_name = f"Components, Road Frames (revised {stamp})"

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

Two behaviors are worth noticing:

- **The `type` filter is doing real work.** `productMeta` holds 200 tag documents alongside the categories. Without the filter, a tag rename would write a tag's name into `categoryName` on unrelated products.
- **The consumer starts from now.** Changes made before it first ran are invisible to it, because the start position applies only until a lease or continuation token exists.

> &#10071; This pull-mode sample keeps its continuation token only in memory. If you stop it, rename the category, and restart it, it starts from `Now` and doesn't replay the intervening change. Rename again while it is running to confirm processing. A production pull consumer must persist its token after successful processing and reload it on restart; this sample doesn't provide durable checkpoints.

## Task 3: React to changes with an Azure Function

The consumer in Task 2 is a process you have to host or an application. In this task you run the equivalent logic on an Azure Functions instead, watching the `product` container so that the changes performed in Task 2 become this task's input.

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
@app.cosmos_db_trigger(
    arg_name="changes",
    database_name="%COSMOS_DATABASE_NAME%",
    container_name="%COSMOS_CONTAINER_NAME%",
    connection="COSMOS_CONNECTION",
    lease_container_name="leases",
)
def product_audit(changes: func.DocumentList) -> None:
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

Azurite emulates Azure Storage on your own machine. The Functions host keeps its internal bookkeeping in a storage account, which is what `AzureWebJobsStorage` points at, and `UseDevelopmentStorage=true` sends that to Azurite. None of your data goes there: the catalog stays in Cosmos DB, and the change feed's checkpoints stay in the `leases` container.

Start Azurite in this terminal (this application can take a few moments to initialize):

```bash
azurite --silent
```

Start the function in a new terminal on this folder:

```bash
func start
```

> &#128221; Select **Allow** if the function requests network access.


The connection setting names an endpoint but no credential, so `DefaultAzureCredential` falls back to your `az login` session. Note what's absent from the trigger configuration: `CreateLeaseContainerIfNotExists` stays at its default, because creating a container is a control-plane operation that a data-plane role assignment doesn't permit. The `leases` container from Task 1 is already there.

Now watch the whole pipeline run:

1. Go to the terminal you used for the rename program and run it again.

1. Watch the Task 2 consumer. It reports the category it synced and how many products it patched.

1. Watch the `func start` terminal. Each patched product arrives as a separate execution, and the message is the one your own function logs:

    ```output
    Product 0AE1D2B4-... is now in category 'Components, Road Frames (revised 051233)'.
    ```

Two consumers are now reading two different feeds from the same account, and one feeds the other. The Task 2 consumer watches `productMeta` and writes to `product`. The function watches `product`, so the consumer's writes are what trigger it.

> &#128221; Both consumers share the `leases` container without colliding, because they monitor different containers and use different processor identities. Two consumers on the *same* monitored container would compete for the same leases, and one of them would sit idle. That case needs a distinct lease container prefix.

## Task 4: Copy a container onto a new partition key

Moving a container to a different partition key means copying its data into a container created with the new key. This task runs that copy yourself, with the CLI.

> &#128221; Container copy jobs are in preview. The jobs run on a best-effort basis with no service-level agreement.

Stop everything still running from the previous tasks, then close those terminals. An offline copy job requires writes on the source to be stopped, and the Task 2 consumer is the process writing to `product`. Updates made after the job starts might not be captured.

The rest of this task runs in the Azure CLI. In the **Explorer** pane, open the context menu for the **Allfiles/Labs/Shared** folder and select **Open in Integrated Terminal**, then sign in:

```azurecli
az login
```

Set the variables again, replacing `ResourceGroup1` if your lab environment provides a different resource group name. The ones you set during setup belonged to a terminal you just closed, and every command below uses them:

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

The copy commands currently ship in a preview extension. Install it:

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

The command returns as soon as the job is registered, before any data moves, so the response reports `"status": "Pending"` with `"totalCount": 0` and `"processedCount": 0`.

Monitor it, give it a few moments, and you need to run the `az cosmosdb copy show` command repeatedly until the `status` reads `Completed`:

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

Read `status` to decide whether the job is finished. Don't rely on the two counts matching: they both sit at zero while the job is still pending, so they match before any work happens. Run the command again until `status` reads `Completed`. A job that fails reports `Faulted` and puts the reason in the `error` property.

The job reads the source container's change feed, which is the same mechanism the previous two tasks used. `totalCount` is what the job found to copy and `processedCount` is what it wrote, so a completed job shows the same number twice.

Confirm the copy in the Azure portal: open **Data Explorer**, select the `productArchive` container, and run `SELECT VALUE COUNT(1) FROM c`. It returns 295, the same count `product` holds.

The items themselves are unchanged, and each one keeps its original `id`. What changed is the container around them: `product` partitions on `/categoryId`, while `productArchive` partitions on `/id`.

The same job shape moves a container onto a hierarchical partition key, which is one of the documented reasons to run a copy. Before running that migration on your own container, confirm that the combination of `id` and the new partition key value stays unique across the container, because uniqueness is enforced on that pair and a collision fails the job.

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
