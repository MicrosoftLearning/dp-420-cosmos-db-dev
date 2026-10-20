---
lab:
  title: Connect an app to Azure Cosmos DB in Python
  module: Module 3 - Connect to Azure Cosmos DB with the SDK
  description: Import the SDK, create a singleton client, run against the emulator, switch to a cloud account, and add basic logging and error handling.
  duration: 30 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Connect an app to Azure Cosmos DB in Python

In this exercise, you connect an SDK application to the local Azure Cosmos DB emulator, add logging and error handling, and then connect the same application to a cloud account with Microsoft Entra authentication.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

Install the **Azure Cosmos DB emulator** using the [local development guide](/azure/cosmos-db/how-to-develop-emulator). Use the Windows emulator or legacy Linux container image on an x64 host for this exercise.

## Set up your Azure Cosmos DB resources

Most of this exercise runs against the local emulator. The final task uses the verified core account described below.

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

1. Set the resource group and region variables. If your lab environment provides a resource group, replace `ResourceGroup1` with its exact name and use a permitted region. Don't create a different resource group. Otherwise, use a resource group and region in your own subscription.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab03 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab03a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint in the final task, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The `core` profile prepares a shared account for this exercise and later exercises. It creates the following resources. This exercise uses the `product` container in the cloud account.

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds the five containers in the `core` profile |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 metadata items |
| `operations` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, initially empty |
| `bulkload` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, initially empty |
| `leases` container | Partitioned on `/id`, manual throughput of 400 RU/s, initially empty |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

The four autoscale containers each have their own 1,000 RU/s maximum. The `leases` container has separate manual throughput. Provisioned throughput incurs charges even when the containers are empty.

Use the public emulator key only for local development. The cloud account disables key-based authentication and uses your Azure CLI identity through `AzureCliCredential`.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Set up the project and install the SDK

1. Create a new directory for the project and open it in your terminal:

    ```bash
    mkdir cosmos-connect-exercise
    cd cosmos-connect-exercise
    ```

1. Install the Azure Cosmos DB SDK and Azure Identity library:

    ```bash
    pip install azure-cosmos azure-identity
    ```

1. Create a new file named **app.py** and add the following imports at the top:

    ```python
    import logging
    import sys
    from azure.cosmos import CosmosClient, exceptions
    from azure.identity import AzureCliCredential
    ```

> &#10071; Build a single file across Tasks 2 through 6. Keep the client markers shown in the code; later tasks use them to identify which block to replace.

---

## Task 2: Start the emulator and read account properties

The emulator provides a local endpoint at `https://localhost:8081/` and uses a documented public key. It doesn't require an Azure connection.

1. Start the emulator.

    On Windows, select **Azure Cosmos DB Emulator** from the **Start** menu, or run the executable directly:

    ```powershell
    & "$env:ProgramFiles\Azure Cosmos DB Emulator\Microsoft.Azure.Cosmos.Emulator.exe"
    ```

    If Windows displays a **User Account Control** prompt, verify that the publisher is **Microsoft Corporation** before approving. Ask your lab administrator if credentials are required; don't disable User Account Control.

    If you installed the container image instead, start it with:

    ```bash
    docker run --publish 8081:8081 --publish 10250-10255:10250-10255 --name cosmos-emulator --detach mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest
    ```

1. Wait a minute or two for the emulator to finish starting.

1. Confirm that the emulator is running by opening **Data Explorer** at `https://localhost:8081/_explorer/index.html`.

    Keep the emulator running for Tasks 2 through 5.

1. In **app.py**, below the imports, add the emulator connection constants and client initialization:

    ```python
    endpoint = "https://localhost:8081/"
    key = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="

    # ==== CLIENT ==== Task 6 replaces this section.
    # connection_verify=False bypasses SSL validation for the local emulator only
    client = CosmosClient(url=endpoint, credential=key, connection_verify=False)
    # ==== END CLIENT ====
    ```

    > &#9888; `connection_verify=False` disables SSL certificate validation. ***Use this setting only for the local emulator; never use it in production code***. Alternatively, import the emulator certificate and remove this parameter.

1. To verify the connection, read account properties. Add the `main` function and the call to it at the bottom of the file:

    ```python
    # This reads account metadata from the service, not an item in a container.
    def main():
        account = client.get_database_account()
        # DatabaseAccount exposes PascalCase attributes
        print(f"Account endpoint: {endpoint}")
        print(f"Consistency:      {account.ConsistencyPolicy}")

        # ---- Tasks 3 and 5 add their code below this line, inside main() ----


    main()
    ```

    Add the code for Tasks 3 and 5 inside `main`, below its marker. Keep the four-space indentation and leave the `main()` call as the last line of the file.

1. Run the script:

    ```bash
    python app.py
    ```

1. Verify that the output shows the emulator endpoint and the default consistency policy.

---

## Task 3: Create the database and container, then reference them in code

The emulator starts empty, so create the `cosmicworks` database and `product` container in its **Data Explorer**. The setup script already created the same pair in your cloud account.

1. Open the emulator's **Data Explorer** at `https://localhost:8081/_explorer/index.html`.

1. Select **New Container** and enter the following, then select **OK**:

    | Setting | Value |
    | :--- | :--- |
    | Database ID | **Create new**, `cosmicworks` |
    | Container ID | `product` |
    | Partition key | `/categoryId` |
    | Container throughput | Manual, `400` |

1. In `main`, below the marker comment you added in Task 2, add the following code. Keep the four-space indentation so the code stays inside `main`:

    ```python
        # These calls build references; read() below makes the service request.
        database = client.get_database_client("cosmicworks")
        container = database.get_container_client("product")

        properties = container.read()

        print(f"Database:         {database.id}")
        print(f"Container:        {properties['id']}")
    ```

    The container read confirms that the resource exists and that the application can access it.

1. Run the script again and confirm both names appear in the output.

---

## Task 4: Add a logging handler

Configure SDK logging to inspect request methods, URIs, status codes, and headers.

1. Between the `# ==== END CLIENT ====` marker and the `def main():` line, configure the `azure.cosmos` logger to `DEBUG`. This code is at the top level of the file, not indented inside `main`:

    ```python
    # Send SDK diagnostics to the console.
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.DEBUG,
        format="%(asctime)s %(name)s %(levelname)s %(message)s"
    )
    logging.getLogger("azure.cosmos").setLevel(logging.DEBUG)
    ```

1. Run the script again. The console now shows the HTTP requests the SDK makes, including URIs (Uniform Resource Identifiers), status codes, and headers.

    > &#128161; In production, use `logging.WARNING` or `logging.INFO` to reduce verbosity. `logging.DEBUG` is valuable for diagnosing individual operations during development.

---

## Task 5: Handle a missing-item error

Read a nonexistent item and inspect the SDK exception and status code.

1. Below the two `print` lines that show the database and container names, still indented four spaces so it stays inside `main`, add a `try/except` block that attempts to read a nonexistent item:

    ```python
        try:
            # A nonexistent ID and partition key deliberately exercise error handling.
            container.read_item(
                item="nonexistent-id",
                partition_key="nonexistent-category"
            )
        except exceptions.CosmosResourceNotFoundError as ex:
            # Inspect the exception's status code.
            print(f"\nCaught CosmosResourceNotFoundError:")
            print(f"  Status code:    {ex.status_code}")
            print(f"  Is retryable:   {ex.status_code in (429, 503)}")
        except exceptions.CosmosHttpResponseError as ex:
            print(f"\nCaught CosmosHttpResponseError:")
            print(f"  Status code:    {ex.status_code}")
            print(f"  Is retryable:   {ex.status_code in (429, 503)}")
    ```

1. Run the script. Confirm that the output shows **404 Not Found** and that `Is retryable` is `False`.

---

## Task 6: Point the app at the cloud account

Connect the application to the cloud account using `AzureCliCredential` and your Azure CLI sign-in. Keep the existing account read, container access, logging, and error handling.

1. Point `endpoint` at the account the setup script printed, and delete the `key` line. Key-based authentication is disabled for this account:

    ```python
    endpoint = "<cosmos-endpoint>"
    ```

1. Replace everything between the `# ==== CLIENT ====` markers with the following code:

    ```python
    # ==== CLIENT ====
    # Explicitly use az login and restore normal TLS certificate validation.
    client = CosmosClient(url=endpoint, credential=AzureCliCredential())
    # ==== END CLIENT ====
    ```

1. Run the script:

    ```bash
    python app.py
    ```

1. Confirm that the output identifies your cloud account and the `product` container. The intentional 404 from Task 5 should still appear.

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
