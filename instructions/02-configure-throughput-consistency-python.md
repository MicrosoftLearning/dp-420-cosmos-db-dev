---
lab:
  title: Configure throughput and consistency in Python
  module: Module 2 - Configure resources, throughput, and consistency
  description: Configure autoscale throughput, set default and per-request consistency, and configure time to live, observing the effects on cost and behavior.
  duration: 30 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you apply the three levers from this module. Provision autoscale throughput for the Contoso workload's bursty traffic. Set an account default consistency level, then relax an individual read below it when needed. Configure time to live so temporary records expire on their own, without a cleanup job. Use a disposable container for the container-wide expiration test to protect the shared product catalog. Along the way, you read the actual request-unit charge of an operation, which is the measurement that turns a throughput estimate into a real number.

This exercise takes approximately **30** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab02 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab02a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds the containers for the `core` lab profile |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 metadata items |
| `leases` container | Partitioned on `/id`, manual throughput of 400 RU/s |
| `operations` and `bulkload` containers | Each partitioned on `/categoryId`, with its own autoscale maximum of 1,000 RU/s |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Review the autoscale range

Autoscale scales between 10 percent of the maximum you set and that maximum. Confirm that range in the portal.

1. In a web browser, open the [Azure portal](https://portal.azure.com), sign in, and go to your Azure Cosmos DB account.

1. In the resource menu, select **Data Explorer**.

1. In the **Data Explorer** pane, expand the **`cosmicworks`** database, select the **product** container, and then select **Scale and Settings**.

1. Review the **Scale** section. The **Autoscale** option is selected, and the maximum throughput is **1,000 RU/s**.

    Note the description of the scaling range. The container scales between **100 RU/s** and **1,000 RU/s** based on real-time demand. Billing uses the highest throughput reached during each hour, with a minimum charge for 100 RU/s even when idle. With dynamic scaling, the bill combines the hourly peaks for each physical partition and region.

1. Change **Maximum RU/s** to `4000` and select **Save**. Wait for the update to finish and confirm that the displayed range is **400 RU/s** to **4,000 RU/s**.

    The minimum rises to 400 RU/s. Raising the ceiling raises the floor, which is why a high autoscale maximum increases your baseline cost.

1. Set **Maximum RU/s** back to `1000` and select **Save**. Wait for the update to finish and confirm that the displayed range returns to **100 RU/s** to **1,000 RU/s**.

1. Open the context menu for **product** in the database tree and select **New SQL Query**. Confirm that the query tab belongs to **product**, then run the following query to confirm that the loaded count is 295:

    ```sql
    SELECT COUNT(1) AS itemCount
    FROM c
    ```
   
## Set the account default consistency level

The account default applies to every read unless a client or request relaxes it. Set it to **strong** so you can observe the cost difference when you relax it.

1. In the **Settings** menu, select **Default consistency**.

1. Select **Strong**, and then select **Save**.

1. Wait for the change to apply before continuing.

    > &#128221; Strong consistency requires a read from more than one replica to guarantee the latest write. That extra work shows up directly in the request charge you measure next.

## Measure the request charge at each consistency level

Now connect from code and compare the request charge of the same read at strong and eventual consistency.

1. In a terminal, create a project folder and set up a virtual environment:

    ```bash
    mkdir throughput-lab
    cd throughput-lab
    python -m venv .venv
    ```

1. Activate the environment. On Windows:

    ```powershell
    .venv\Scripts\activate
    ```

    On macOS or Linux:

    ```bash
    source .venv/bin/activate
    ```

1. Install the required packages:

    ```bash
    pip install azure-cosmos azure-identity
    ```

1. In the **throughput-lab** folder, alongside the **`.venv`** folder rather than inside it, create a file named **script.py** and add the following code. Replace `<cosmos-endpoint>` with the account endpoint the setup script printed:

    ```python
    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential

    endpoint = "<cosmos-endpoint>"

    client = CosmosClient(url=endpoint, credential=DefaultAzureCredential())
    container = client.get_database_client("cosmicworks").get_container_client("product")

    item_id = "0A7E57DA-C73F-467F-954F-17B7AFD6227E"
    partition_key = "4F34E180-384D-42FC-AC10-FEC30227577F"

    def print_charge(label):
        def hook(headers, response):
            print(f"{label} request charge:\t{headers['x-ms-request-charge']} RUs")
        return hook

    container.read_item(
        item=item_id,
        partition_key=partition_key,
        response_hook=print_charge("STRONG"))
    ```

    `DefaultAzureCredential` picks up the identity you signed in with through the Azure CLI, so no key appears in the code. The `response_hook` callback receives the response headers, where `x-ms-request-charge` reports the exact RU cost of the read.

1. Run the script:

    ```bash
    python script.py
    ```

1. Review the output. The charge reflects strong consistency:

    ```output
    STRONG request charge:  2 RUs
    ```

1. Now relax the consistency level. The Python SDK sets consistency at the client level, so create a second client configured for eventual consistency. Add the following code to the end of **script.py**:

    ```python
    eventual_client = CosmosClient(
        url=endpoint,
        credential=DefaultAzureCredential(),
        consistency_level="Eventual")

    eventual_container = (eventual_client
        .get_database_client("cosmicworks")
        .get_container_client("product"))

    eventual_container.read_item(
        item=item_id,
        partition_key=partition_key,
        response_hook=print_charge("EVENTUAL"))
    ```

    The `consistency_level` argument relaxes every read from this client below the account default.

1. Run the script again:

    ```bash
    python script.py
    ```

1. Compare the two charges:

    ```output
    STRONG request charge:    2 RUs
    EVENTUAL request charge:  1 RUs
    ```

    Your exact values might differ slightly, but the strong read costs about twice the eventual one. The eventual read is served from a single replica instead of requiring agreement across replicas. On a read-heavy workload running thousands of operations per second, relaxing the reads that tolerate staleness is a direct and substantial cost reduction.

1. Relaxing works in one direction only. The account default is the strongest level a client can use, so setting `consistency_level` above it isn't supported. When an operation needs a stronger guarantee, raise the account default and relax the other reads instead.


1. When you finish testing, deactivate the Python environment:

    ```bash
    deactivate
    ```

## Restore the account default consistency

*Strong* consistency roughly doubles the cost of every read, so set the account back to *Session*.

1. Return to the Azure portal and open your Azure Cosmos DB account.

1. In the **Settings** menu, select **Default consistency**.

1. Select **Session**, and then select **Save**.

    Session is the default level for a new account. Wait for the change to apply, then restart any application with an existing SDK client so it picks up the new default. Each new run of the console application or Python script creates a new client.

## Configure time to live and observe expiry

Finally, configure automatic data retention on the container.

1. Return to the Azure portal and open the **Data Explorer**.

1. Expand the **`cosmicworks`** database, select the **`product`** container, and then select **Scale and Settings**.

1. In the **Settings** tab, find **Time to Live** and select **On (no default)**.

    This setting corresponds to a `DefaultTimeToLive` value of `-1`. It enables the TTL mechanism without expiring existing items, which lets individual items opt in to expiration.

1. Select **Save**.

1. Select **Items**, and then select **New Item**. Add an item with a **`ttl`** property set to 60 seconds, and then select **Save**:

    ```json
    {
      "id": "temp-record-001",
      "categoryId": "4F34E180-384D-42FC-AC10-FEC30227577F",
      "name": "Temporary record",
      "ttl": 60
    }
    ```

1. Select **New SQL Query** under the **product** container and run the following query:

    ```sql
    SELECT * FROM c WHERE c.id = "temp-record-001"
    ```

    Initially, the query returns the item you just added.

1. Wait about 90 seconds, then run the query again.

    The expired `temp-record-001` item no longer appears in query results. Physical deletion runs in the background and might finish later. The `ML Road Pedal` item remains, because it has no **`ttl`** property and the container default is `-1`.

    The pattern for mixed retention in a single container is to enable Time to Live (TTL) on the container, then set `ttl` only on the items that should expire.

1. In the **product** container's **Scale and Settings**, change **Time to Live** back to **Off** and select **Save**. Wait for the update to finish.

    > &#9888; Don't set a positive default TTL on the shared product catalog. Expiration is measured from each item's last modification, not from when TTL is enabled. Existing items older than the default TTL can expire immediately.

1. Run the temporary-item query again after TTL is **Off**. An expired item can reappear if background deletion is incomplete when you disable TTL. If `temp-record-001` reappears, open **Items**, filter for `WHERE c.id = "temp-record-001"`, and select that item. Verify its ID and **categoryId** match the test item, then select **Delete** and confirm. Run the query again and confirm that no item remains. Don't delete catalog products.

1. In **Data Explorer**, create a new container named **ttl-demo** in the existing **cosmicworks** database. Use `/categoryId` as the partition key and dedicated autoscale throughput with a maximum of **1,000 RU/s**. If that name already exists, use a new, unused name for this test.

1. Open the new container's **Scale and Settings**. Set **Time to Live** to **On**, enter `60` seconds, and select **Save**.

1. In the new container, add this item without a `ttl` property:

    ```json
    {
      "id": "temp-record-001",
      "categoryId": "4F34E180-384D-42FC-AC10-FEC30227577F",
      "name": "Temporary record"
    }
    ```

    In this disposable container, every item without its own `ttl` expires 60 seconds after its last modification.

1. Open the context menu for the new container and select **New SQL Query**. Confirm that the query tab belongs to that container, then run `SELECT * FROM c WHERE c.id = "temp-record-001"`. Wait about 90 seconds, then run it again. The item no longer appears because it inherits the container's default TTL.

1. Delete only the disposable **ttl-demo** container, or the alternative name you used, to stop its throughput charges. Keep **product** and the other shared lab containers.

1. In **product**, confirm that **Time to Live** is **Off**, the temporary-item query returns no result, and `SELECT VALUE COUNT(1) FROM c` returns 295 before reusing this catalog.


## Clean up resources

When you finish the course, delete the resource group only if you created it and every resource in it can be removed. If your lab provided `ResourceGroup1`, skip this command and delete only the exercise resources you no longer need:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name <your-account-name> --resource-group $resourceGroup --yes
```

You configured all three cost and performance levers: autoscale throughput sized to bursty traffic, a consistency level relaxed per request where staleness is acceptable, and time to live for automatic retention. The request-charge comparison you measured shows how consistency affects read cost; workload measurements and the billing model guide throughput sizing.

