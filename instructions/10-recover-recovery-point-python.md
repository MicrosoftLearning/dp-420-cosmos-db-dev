---
lab:
  title: Recover from a recovery point in Python
  module: Module 10 - Configure Backup and Restore in Azure Cosmos DB
  description: Enable continuous backup on an Azure Cosmos DB for NoSQL account, delete a product and its container, and restore both to a recorded point in time.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Recover from a recovery point in Python

In this exercise, you protect an Azure Cosmos DB for NoSQL account with continuous backup, destroy data the way an accidental operation would, and recover it to a point in time you choose. You work with the real CosmicWorks product catalog, so the verification steps compare against actual data rather than placeholder values.

You load 295 products into an account provisioned at the `Continuous7Days` tier, capture a verified restore point, delete an item and then the container that held it, and restore the container into the same account. You finish by testing whether repeating that restore recovers another deleted item from the live container, and by removing everything you created.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

You also need permission to discover restorable accounts and restore their resources. For the CLI workflow in this exercise, ask your administrator for the **CosmosRestoreOperator** role at subscription scope, or equivalent permissions. Resource-group permissions and the data-plane role created by the setup script don't grant these actions. See [restore permissions](/azure/cosmos-db/continuous-backup-restore-permissions).

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

The in-account restore commands need [Azure CLI](/cli/azure/install-azure-cli) version 2.65.0 or later. Earlier versions don't accept the `--disable-ttl` option this exercise uses.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path. Enabling continuous backup on an existing account is a one-way migration, and this exercise deletes and restores the container it works in.

> &#9888; Use only the account this script creates for this exercise. Later steps delete a container and then restore it. Never point this exercise at a shared training or production account.

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

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab10 -LabProfile backup
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab10a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Confirm the applied backup policy.

    ```azurecli
    az cosmosdb show --name $accountName --resource-group $resourceGroup --query "backupPolicy"
    ```

    The output reports a `type` of `Continuous`, a `tier` of `Continuous7Days`, and a `migrationState` of `null`. Naming the tier is deliberate: an account created without `--continuous-tier` gets the charged 30-day tier.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled and continuous backup at the `Continuous7Days` tier |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, 400 RU/s, and empty. You load it yourself, so the restore point you capture sits after a write you made |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The SDK examples use `AzureCliCredential` to select the identity from your `az login` session. Microsoft Entra ID authentication is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

This exercise creates billable resources. The `Continuous7Days` tier has no backup storage charge, but the account itself, its provisioned throughput, and the restore operation are billable. Complete the cleanup task when you finish.

## Task 1: Load the catalog and capture a restore point

1. In your Windows PowerShell terminal, create the project folder and a virtual environment, activate it, and install the packages.

    ```powershell
    mkdir catalog-recovery
    cd catalog-recovery
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install azure-cosmos azure-identity truststore
    ```

    Activation makes `python` use the virtual environment for this terminal session. Using `python -m pip` installs the packages with that same Python interpreter.

    If you're using Bash on Linux or macOS, replace the activation line with `source .venv/bin/activate`. The `source` command doesn't work in PowerShell.

    The `azure-cosmos` package provides the client for item operations and queries. The `azure-identity` package provides `AzureCliCredential`, which authenticates those requests with your Azure CLI sign-in.

    The `truststore` package lets the catalog download use the operating system's native certificate validation. On Windows, this supports certificate-chain building through Windows rather than Python's default OpenSSL implementation. HTTPS certificate and hostname verification remain enabled.

1. Create a file named `catalog.py` with the following code. Replace `<cosmos-endpoint>` with the account endpoint the setup script printed.

    This helper uses the SDK to load, inspect, and delete catalog data. It doesn't configure backups or restore resources; you use Azure CLI commands for those management operations later in the exercise.

    ```python
    import json
    import ssl
    import sys
    import urllib.request

    import truststore
    from azure.cosmos import CosmosClient
    from azure.cosmos.exceptions import CosmosResourceNotFoundError
    from azure.identity import AzureCliCredential

    ENDPOINT = "<cosmos-endpoint>"
    DATA_URL = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product"

    # Together, the item ID and /categoryId partition key value identify the
    # product used to verify recovery. An item ID alone isn't unique across partitions.
    ITEM_ID = "063F1A00-8CA1-4DB9-8298-BEAC4B8CC238"
    CATEGORY_ID = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F"

    # Use the identity from az login, not an account key.
    client = CosmosClient(ENDPOINT, credential=AzureCliCredential())
    # These calls reference existing resources; they don't create or restore them.
    container = client.get_database_client("cosmicworks").get_container_client("product")

    command = sys.argv[1] if len(sys.argv) > 1 else "count"

    if command == "seed":
        # Use native certificate validation, including Windows certificate-chain
        # building, without disabling HTTPS certificate or hostname verification.
        ssl_context = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        with urllib.request.urlopen(DATA_URL, context=ssl_context) as response:
            products = json.load(response)
        # Upsert creates an item or replaces one with the same ID and partition key.
        # The SDK reads the partition key from each product's categoryId property.
        for product in products:
            container.upsert_item(product)
        print(f"Loaded {len(products)} products.")

    elif command == "read":
        try:
            # A point read goes directly to the product's logical partition.
            item = container.read_item(item=ITEM_ID, partition_key=CATEGORY_ID)
            print(f"Found {item['name']} priced at {item['price']}.")
        except CosmosResourceNotFoundError:
            # A not-found response is expected after the intentional item deletion.
            # Other errors, such as authorization failures, still surface.
            print("The item was not found.")

    elif command == "delete":
        container.delete_item(item=ITEM_ID, partition_key=CATEGORY_ID)
        print("Deleted the item.")

    else:
        # Count across all category partitions, not just the selected product's.
        # SELECT VALUE returns a scalar count; next() reads it from the result iterator.
        count = next(container.query_items(
            "SELECT VALUE COUNT(1) FROM c",
            enable_cross_partition_query=True,
        ))
        print(f"Item count: {count}")
    ```

    The first command-line argument selects the operation:

    | Command | SDK behavior | Purpose in this exercise |
    | :--- | :--- | :--- |
    | `seed` | Downloads the catalog and upserts each product | Establishes the data to back up |
    | `read` | Reads one product by its item ID and partition key | Checks the product's name and price before deletion and after restore |
    | `delete` | Deletes only that product, not the container | Simulates the first accidental data loss |
    | `count` (or no argument) | Counts items across the container | Checks that the catalog contains 295 products before deletion and after restore |

    Run `seed` only when loading the initial catalog. Running it after a restore would recreate missing products and could hide an incomplete recovery. The count checks the catalog size, while the point read checks the selected product's values; neither check alone validates every restored product.

1. Load the catalog.

    ```powershell
    python catalog.py seed
    ```

    The command reports `Loaded 295 products.`

    If the download fails with a certificate-chain error, it fails before any products are written. Ask your lab administrator to check the VM's trusted certificates and any HTTPS-inspecting proxy. Don't disable certificate verification to continue the exercise.

1. Read the product you recover later, and confirm the count.

    ```powershell
    python catalog.py read
    python catalog.py count
    ```

    The read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` and the count reports 295.

1. Ask the service how far its backups reach, and record the value. This timestamp is your restore point.

    ```azurecli
    az cosmosdb sql retrieve-latest-backup-time `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --container-name "product" `
        --location $location
    ```

    The response contains a `latestRestorableTimestamp`. Convert it to the ISO 8601 UTC form the restore command expects, for example `2026-09-06T14:10:00Z`, and keep it available.

    If the command reports a timestamp earlier than your seeding, wait a minute and run it again. Backups catch up asynchronously, and restoring to a point before the writes landed recovers an empty container.

## Task 2: Delete the data and restore it into the same account

1. Delete the product, then confirm it's gone.

    ```powershell
    python catalog.py delete
    python catalog.py read
    ```

    The read now reports `The item was not found.`

1. Delete the container that held it, simulating a broader accidental operation.

    ```azurecli
    az cosmosdb sql container delete `
        --account-name $accountName `
        --resource-group $resourceGroup `
        --database-name "cosmicworks" `
        --name "product" `
        --yes
    ```

1. Find the account's instance identifier and save it in `$instanceId`.

    ```powershell
    $instanceId = az cosmosdb restorable-database-account list `
        --account-name $accountName `
        --query "[?deletionTime==null].name | [0]" `
        --output tsv
    ```

1. Find the `cosmicworks` database's resource identifier and save it in `$ownerResourceId`.

    ```powershell
    $ownerResourceId = az cosmosdb sql restorable-database list `
        --instance-id $instanceId `
        --location $location `
        --query "[?resource.ownerId=='cosmicworks'].resource.ownerResourceId | [0]" `
        --output tsv
    ```

1. List the container events and locate the deletion you just performed.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    Find the `product` row with **Operation** set to `Delete`. **EventTimeUTC** shows when the deletion occurred. Choose a restore timestamp before that deletion, when the container existed in the account's current write region and its data was backed up, within the retention window. The verified post-seed timestamp from Task 1 meets these conditions and predates both deletions.

1. Restore the container into the same account, targeting the timestamp from Task 1.

    ```azurecli
    az cosmosdb sql container restore `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --name "product" `
        --restore-timestamp "<restore-timestamp>" `
        --disable-ttl True
    ```

    > &#128221; The restore could take 5 minutes or more. The container reports a status of `Creating` while it runs. Wait for the restore to finish before running the verification commands in the next step.

    The container has no time-to-live policy, so `--disable-ttl True` changes nothing here. Include it as a habit: restoring a container that does have an expiry policy can delete the recovered items almost immediately.

1. Verify that both the container and the deleted product came back.

    ```powershell
    python catalog.py count
    python catalog.py read
    ```

    The count reports 295 and the read reports `Found Road-350-W Yellow, 48 priced at 1700.99.` One restore recovered both losses, because the restore point predates both the item deletion and the container deletion.

    The account-scoped data-plane role assignment the setup script made continues to apply after this same-account restore. If either command fails with an authorization error, check the error details, your signed-in identity, and its data-plane role assignment. Also check the account's network access settings. Each command starts a new SDK client, so it doesn't reuse session or continuation tokens from the earlier run.

## Task 3: Test the limits of same-account restore

Same-account restore recovers deleted containers, not individual deleted items in a live container. Test the effect of repeating the restore by comparing container history and checking the item, rather than relying on the command's success or failure.

1. After the first restore has finished, list the container events again.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    Record the latest creation or recreation event's **EventTimeUTC** for `product`. You compare this history with the output after the second restore request.

1. Delete only the recovered product item, and confirm it's gone. Don't delete the container or run `seed`.

    ```powershell
    python catalog.py delete
    python catalog.py read
    ```

    The read reports `The item was not found.` The `product` container still exists.

1. Repeat the original restore command, using the same restore timestamp from Task 1.

    ```azurecli
    az cosmosdb sql container restore `
        --resource-group $resourceGroup `
        --account-name $accountName `
        --database-name "cosmicworks" `
        --name "product" `
        --restore-timestamp "<restore-timestamp>" `
        --disable-ttl True
    ```

    Wait for the command to finish. It can return a successful response, but that alone doesn't show that the container or its data was restored again.

1. List the container events again and compare them with the history you recorded.

    ```azurecli
    az cosmosdb sql restorable-container list `
        --instance-id $instanceId `
        --database-rid $ownerResourceId `
        --location $location `
        --query "[].{Container:resource.ownerId,Operation:resource.operationType,EventTimeUTC:resource.eventTimestamp}" `
        --output table
    ```

    The recorded creation or recreation timestamp should be unchanged, with no additional creation or recreation event for `product`.

1. Read the deleted product again.

    ```powershell
    python catalog.py read
    ```

    The read should still report `The item was not found.` Together, the unchanged container creation history and the missing item show that the repeated request didn't recreate the container or recover the item you just deleted. A successful command response isn't proof of data recovery.

1. Consider what the alternative costs. To recover a live container holding wrong data, you restore into a new account with `az cosmosdb restore`, then reconcile the recovered data back into production yourself. That path creates a second billable account, takes considerably longer, and charges a restore fee based on the volume of data restored. Don't run it in this exercise.

1. Review the restore in the account's activity log. In the Azure portal, open the account, select **Activity log**, and filter on **InAccount Restore Deleted**. The entry names the principal that started the restore, which is the evidence an incident review asks for.

## Clean up resources

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources. If your lab provided `ResourceGroup1`, keep the group and use the account-deletion command instead.

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

Deleting the resource group removes the account, the database, the container, and the data-plane role assignment together. If your lab provided the group, or it holds other resources, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

You enabled continuous backup, captured a verified restore point, recovered a deleted container and the item inside it, and tested a repeated restore request by checking container history and item data.
