---
lab:
  title: Diagnose throttling and configure an alert in Python
  module: Module 14 - Monitor and Troubleshoot Azure Cosmos DB
  description: Enable diagnostic logging, drive a container past its provisioned throughput, confirm the rate limiting from client diagnostics, Azure Monitor metrics, and Log Analytics, then create an alert rule.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

In this exercise, you work an incident end to end. You enable diagnostic logging on an Azure Cosmos DB account, drive a container past its provisioned throughput until it starts rate limiting, then confirm what happened from three separate vantage points: the client's own exception handling, Azure Monitor metrics, and a Kusto query over the diagnostic logs. You finish by creating an alert rule so the same condition announces itself next time.

The order of the tasks matters. Diagnostic logs take several minutes to reach Log Analytics after the requests that produce them, so you enable logging first and query it last, with the metrics and alerting work filling the interval.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

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
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab14 -LabProfile monitoring
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab14a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both later in this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

Provisioned throughput values are in request units per second (RU/s). The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, **400 RU/s manual throughput**, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

The container uses manual throughput rather than autoscale on purpose. A fixed 400-RU/s ceiling makes rate limiting easier to reproduce within the lab time budget. Autoscale can absorb more load up to its configured maximum, but requests that exceed that maximum are still rate limited.

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The examples authenticate with Microsoft Entra ID through `DefaultAzureCredential`. This credential can use your `az login` session, but it checks other credential sources first. Make sure the identity it selects has the data-plane role assignment.

> &#9888; Use only the account this script creates for this exercise. Later steps attach a diagnostic setting and an alert rule. Never point this exercise at a shared training or production account.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Send diagnostic logs to a Log Analytics workspace

Metrics are collected without any configuration. Resource logs aren't: nothing is recorded until a diagnostic setting exists. Enabling it first means the requests you generate in the next task are captured.

1. Create a Log Analytics workspace in the same resource group.

    ```azurecli
    az monitor log-analytics workspace create `
        --resource-group $resourceGroup `
        --workspace-name "dp420lab14-logs" `
        --location $location
    ```

1. Capture the resource IDs of the workspace and the Azure Cosmos DB account. The diagnostic setting needs both.

    ```powershell
    $workspaceId = az monitor log-analytics workspace show `
        --resource-group $resourceGroup `
        --workspace-name "dp420lab14-logs" `
        --query "id" --output tsv

    $accountId = az cosmosdb show `
        --resource-group $resourceGroup `
        --name $accountName `
        --query "id" --output tsv
    ```

1. Write the log categories to a file. Collecting `DataPlaneRequests` records every operation individually, and `PartitionKeyRUConsumption` records request unit consumption per logical partition key.

    ```powershell
    $logCategories = Join-Path ([System.IO.Path]::GetTempPath()) "cosmos-log-categories.json"

    '[{"category":"DataPlaneRequests","enabled":true},{"category":"PartitionKeyRUConsumption","enabled":true}]' |
        Set-Content -LiteralPath $logCategories -Encoding utf8
    ```

    PowerShell removes the double quotation marks from an inline JSON argument before the Azure CLI sees it. The Azure CLI's `@<file>` convention avoids the problem by reading the value from the file instead.

1. Create the diagnostic setting.

    ```azurecli
    az monitor diagnostic-settings create `
        --name "cosmos-diagnostics" `
        --resource $accountId `
        --workspace $workspaceId `
        --export-to-resource-specific true `
        --logs "@$logCategories"
    ```

    The `--export-to-resource-specific` argument sends each category to its own strongly typed table rather than to the shared legacy `AzureDiagnostics` table. That decision applies to data ingested from now on, so it can't be changed retroactively.

1. Confirm the setting exists and lists both categories.

    ```azurecli
    az monitor diagnostic-settings show `
        --name "cosmos-diagnostics" `
        --resource $accountId `
        --query "logs[?enabled].category" --output tsv
    ```

    ```output
    DataPlaneRequests
    PartitionKeyRUConsumption
    ```

## Task 2: Drive the container into rate limiting

Now you generate the incident. The application reads every product in the container and upserts each one back, repeatedly, for one minute. At 400 RU/s, that workload asks for far more throughput than the container has.

The Python client allows one retry before a remaining 429 reaches your code. This setting makes throttling easier to observe in the exercise; it isn't the default production retry setting.

1. Open a new integrated terminal in **Visual Studio Code** and create a project folder with a virtual environment.

    ```powershell
    mkdir throttle-lab
    cd throttle-lab
    python -m venv .venv
    .venv\Scripts\activate
    ```

1. Install the packages the script needs.

    ```powershell
    pip install azure-cosmos azure-identity
    ```

1. Create a file named **throttle.py** with the following code, then replace `<cosmos-endpoint>` with the endpoint you recorded earlier.

    ```python
    import time
    from concurrent.futures import ThreadPoolExecutor
    from azure.cosmos import CosmosClient, exceptions
    from azure.identity import DefaultAzureCredential

    endpoint = "<cosmos-endpoint>"

    client = CosmosClient(
        endpoint,
        credential=DefaultAzureCredential(),
        retry_throttle_total=1,
    )

    container = client.get_database_client("cosmicworks").get_container_client("product")

    products = list(container.read_all_items())
    print(f"Read {len(products)} products.")

    succeeded = 0
    throttled = 0
    last_activity_id = ""

    def upsert(item):
        global succeeded, throttled, last_activity_id
        try:
            container.upsert_item(item)
            succeeded += 1
        except exceptions.CosmosHttpResponseError as error:
            if error.status_code == 429:
                throttled += 1
                last_activity_id = error.headers.get("x-ms-activity-id", "")
            else:
                raise

    deadline = time.time() + 60

    with ThreadPoolExecutor(max_workers=16) as pool:
        while time.time() < deadline:
            list(pool.map(upsert, products))

    print(f"Succeeded: {succeeded}")
    print(f"Rate limited (429): {throttled}")
    print(f"Activity ID of a rate-limited request: {last_activity_id}")
    ```

    The `retry_throttle_total` value is `1` rather than `0` on purpose. The Python SDK treats zero as *unset* and falls back to its default of nine retries, so passing `1` is the lowest value that reduces the retrying and lets 429 responses reach your code.

1. Run the script. It takes about a minute plus the time to read the container.

    ```powershell
    python throttle.py
    ```

    ```output
    Read 295 products.
    Succeeded: 2765
    Rate limited (429): 1102
    Activity ID of a rate-limited request: 4f2c8b1e-6a3d-4c05-9f7b-1d2e3a4b5c6d
    ```

1. Record your rate-limited count and the activity ID. You use the activity ID in Task 5.

    Your numbers differ from the sample values, and they should. Throughput consumption depends on item size, region, and how much concurrency your machine sustains. What matters is the shape of the result: a substantial fraction of requests rejected, against a container that never went down and never returned an error other than 429.

## Task 3: Confirm the throttling in Azure Monitor metrics

The client saw its own failures. Now confirm the same event from the service's side, where the count includes every rate-limited response rather than only the ones that reached your code.

1. In a browser, open the [Azure portal](https://portal.azure.com) and go to the Azure Cosmos DB account this exercise created.

1. In the resource menu, under **Monitoring**, select **Insights**.

1. Select the **Requests** tab and find the **Total Requests by Status Code** chart. Set the time range to the last hour.

    The chart shows a block of 429 responses alongside the successful ones, aligned with the minute your application ran.

1. Select the **Throughput** tab and find the **Normalized RU Consumption (%) By PartitionKeyRangeID** chart.

    The container sits at 100 percent for the duration of the run. Note how many separate lines the chart draws: at 295 items the container occupies a single physical partition, so there's one line. In a container large enough to have split, this chart is how you tell a container that needs more throughput from one with a hot partition.

1. In the resource menu, select **Metrics**, then choose the **Total Requests** metric with the **Count** aggregation.

1. Select **Apply splitting**, choose the `StatusCode` dimension, and set the time range to the last hour.

    The split chart separates the status codes present in the selected window. Successful upserts of the existing products return 200; an upsert returns 201 only when it creates an item. Compare the 429 count here with the count your application reported.

    The service's count includes attempts retried inside the SDK, while the application counts only operations that still fail after the permitted retry. Increasing `retry_throttle_total` can reduce application-visible failures, but it also changes this timed workload's pacing and request volume. The service's 429 count isn't guaranteed to remain the same between runs.

## Task 4: Create an alert on rate-limited requests

The event is over. An alert makes sure you hear about the next one without watching a chart.

1. Return to the terminal and create an action group. Replace the email address with your own.

    ```azurecli
    az monitor action-group create `
        --name "dp420lab14-oncall" `
        --resource-group $resourceGroup `
        --short-name "dp420lab14" `
        --action email oncall you@contoso.com
    ```

1. Capture the action group's resource ID.

    ```powershell
    $actionGroupId = az monitor action-group show `
        --name "dp420lab14-oncall" `
        --resource-group $resourceGroup `
        --query "id" --output tsv
    ```

1. Create a metric alert rule scoped to the account, watching the **Total Requests** metric filtered to a `StatusCode` of `429`.

    ```azurecli
    az monitor metrics alert create `
        --name "Rate limited requests" `
        --resource-group $resourceGroup `
        --scopes $accountId `
        --condition "count TotalRequests > 100 where StatusCode includes 429" `
        --window-size 5m `
        --evaluation-frequency 1m `
        --action $actionGroupId `
        --description "More than 100 rate-limited requests in five minutes."
    ```

1. Confirm the rule exists and is enabled.

    ```azurecli
    az monitor metrics alert show `
        --name "Rate limited requests" `
        --resource-group $resourceGroup `
        --query "{name:name, enabled:enabled, severity:severity, window:windowSize}"
    ```

    ```output
    {
      "enabled": true,
      "name": "Rate limited requests",
      "severity": 2,
      "window": "0:05:00"
    }
    ```

    A threshold of 100 suits this exercise, where the container is small and the load is deliberate. On a real workload, size the threshold against expected traffic. If 1 to 5 percent of requests returning 429 is healthy for your account, a threshold below that band fires constantly and gets muted, which leaves you worse off than having no rule.

    The rule becomes active within about 10 minutes. It can still fire if the earlier load remains inside its five-minute lookback window. Once that load falls outside the window, it no longer contributes to the rule's request count.

## Task 5: Find the throttled operations in Log Analytics

Metrics told you that throttling happened and roughly when. Logs tell you which operation caused it and what each call cost.

1. In the Azure portal, return to the Azure Cosmos DB account and select **Logs** under **Monitoring**. Close the queries dialog if it opens.

1. Run the following query to find the share of requests that were rate limited, broken down by operation.

    ```kusto
    CDBDataPlaneRequests
    | where TimeGenerated >= ago(1h)
    | summarize throttledOperations = dcountif(ActivityId, StatusCode == 429),
                totalOperations = dcount(ActivityId),
                totalConsumedRU = sum(RequestCharge)
        by OperationName, bin(TimeGenerated, 1min)
    | extend averageRUPerOperation = 1.0 * totalConsumedRU / totalOperations
    | extend fractionOf429s = 1.0 * throttledOperations / totalOperations
    | order by fractionOf429s desc
    ```

    If the query returns nothing, the logs haven't finished arriving. Wait a few minutes and run it again.

    The result names `Upsert` as the operation being rate limited, reports the average request charge of each call, and shows the fraction rejected in each minute. That's the level of detail that tells you whether to raise throughput, reduce the write rate, or make each write cheaper.

1. Run the following query to see request unit consumption per logical partition key.

    ```kusto
    CDBPartitionKeyRUConsumption
    | where TimeGenerated >= ago(1h)
    | where CollectionName == "product"
    | where isnotempty(PartitionKey)
    | summarize sum(RequestCharge) by PartitionKey, bin(TimeGenerated, 1s)
    | order by sum_RequestCharge desc
    ```

    Each row is one `categoryId` value in one second. The workload touches every category, but categories contain different numbers of products and writes can have different request charges. Compare the measured consumption across keys. Touching every category doesn't prove that the load is evenly distributed or rule out a hot key.

1. Look up the specific request behind the activity ID your application printed. Replace the placeholder with the value you recorded.

    ```kusto
    CDBDataPlaneRequests
    | where ActivityId == "<your-activity-id>"
    | project TimeGenerated, OperationName, StatusCode, RequestCharge, DurationMs
    ```

    One row comes back: the exact request your application saw fail, as the service recorded it. That join between an application's exception and a service's log entry is what turns "some writes are failing" into a specific, reproducible finding.

## Clean up resources

This exercise creates an Azure Cosmos DB account, a Log Analytics workspace, an alert rule, and an action group. Remove the resources you created when you finish. Provisioned throughput remains billable even without requests, and Log Analytics can charge for data ingestion and retention.

Deleting the diagnostic setting first is deliberate. A setting left behind can attach itself to a resource later recreated with the same name and quietly resume ingesting.

```azurecli
az monitor diagnostic-settings delete `
    --name "cosmos-diagnostics" `
    --resource $accountId
```

Delete the resource group only if you created it for this exercise and it contains only this exercise's resources:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab provided `ResourceGroup1`, or the group holds other resources, keep the group. In the Azure portal, delete only this exercise's account, Log Analytics workspace, alert rule, and action group.

You diagnosed the same event three times, from the application's exceptions, from platform metrics, and from diagnostic logs, and each pass answered a question the previous one raised. That progression, from a symptom to a measurement to a specific operation, is the shape of every Azure Cosmos DB investigation worth doing.
