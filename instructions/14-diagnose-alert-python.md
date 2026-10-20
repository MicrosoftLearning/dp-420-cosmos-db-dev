---
lab:
  title: Diagnose throttling and configure an alert in Python
  module: Module 14 - Monitor and Troubleshoot Azure Cosmos DB
  description: Generate throttling, investigate client diagnostics and Azure Monitor metrics, configure a metric alert, and analyze synthetic diagnostic records with KQL.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Diagnose throttling and configure an alert in Python

In this exercise, you generate rate limiting on an Azure Cosmos DB account, investigate client diagnostics and Azure Monitor metrics, and configure an alert. You then use Kusto Query Language (KQL) to analyze synthetic diagnostic records and find a request by its activity ID.

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

1. Capture the account ID and endpoint. Keep using this PowerShell terminal throughout the exercise so these variables remain available.

    ```powershell
    $account = az cosmosdb show `
        --resource-group $resourceGroup `
        --name $accountName --output json | ConvertFrom-Json
    $accountId = $account.id
    $endpoint = $account.documentEndpoint
    ```

Provisioned throughput values are in request units per second (RU/s). The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, **400 RU/s manual throughput**, loaded with 295 CosmicWorks products |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

The fixed 400-RU/s limit makes it easier to observe throttling under load.

The application authenticates with Microsoft Entra ID through `DefaultAzureCredential`. This credential can use your `az login` session, but it checks other credential sources first. Make sure the identity it selects has the data-plane role assignment.

> &#9888; Use only the account this script creates for this exercise. Later steps attach a diagnostic setting and an alert rule. Never point this exercise at a shared training or production account.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Configure diagnostic logging and a metric alert

Platform metrics are collected automatically; diagnostic logs are opt-in. Configure a log destination and an alert on rate-limited requests before generating load. The alert uses platform metrics, not diagnostic logs.

1. From the **Allfiles/Labs/Shared** terminal, create a Log Analytics workspace and capture its resource ID.

    ```powershell
    $workspaceId = az monitor log-analytics workspace create `
        --resource-group $resourceGroup `
        --workspace-name "dp420lab14-logs" `
        --location $location `
        --query "id" --output tsv
    ```

1. Create a JSON file that enables `DataPlaneRequests` for request-level details and `PartitionKeyRUConsumption` for logical partition key consumption.

    ```powershell
    $logCategories = Join-Path ([System.IO.Path]::GetTempPath()) "cosmos-log-categories.json"
    '[{"category":"DataPlaneRequests","enabled":true},{"category":"PartitionKeyRUConsumption","enabled":true}]' |
        Set-Content -LiteralPath $logCategories -Encoding utf8
    ```

1. Create a diagnostic setting using the file.

    ```azurecli
    az monitor diagnostic-settings create `
        --name "cosmos-diagnostics" `
        --resource $accountId `
        --workspace $workspaceId `
        --export-to-resource-specific true `
        --logs "@$logCategories"
    ```

    The `@<file>` argument reads the log categories from the JSON file. Resource-specific mode stores the logs in `CDBDataPlaneRequests` and `CDBPartitionKeyRUConsumption`. Request logs can incur ingestion and retention charges.

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

1. Create an action group and capture its resource ID. Replace the email address with your own. You might receive an action-group confirmation email.

    ```powershell
    $actionGroupId = az monitor action-group create `
        --name "dp420lab14-oncall" `
        --resource-group $resourceGroup `
        --short-name "dp420lab14" `
        --action email oncall you@contoso.com `
        --query id --output tsv
    ```

1. Create a metric alert scoped to the account. It counts **Total Requests** filtered to a `StatusCode` of `429`.

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

1. Verify the rule's scope, condition, action group, and enabled state.

    ```azurecli
    az monitor metrics alert show `
        --name "Rate limited requests" `
        --resource-group $resourceGroup `
        --query "{enabled:enabled, scopes:scopes, condition:criteria.allOf, actions:actions}"
    ```

    Confirm `enabled` is `true`, the scope is your account ID, the metric is `TotalRequests` with `Count` aggregation, the threshold is `100`, the dimension selects `429`, and the action references your action group. Explain why removing the status-code dimension would change the alert's meaning.

    The rule can take about 10 minutes to become active. Continue to Task 2 without waiting for an alert notification. For a production workload, choose a threshold based on expected traffic and acceptable latency.

## Task 2: Drive the container into rate limiting

The application reads the products once, then repeatedly upserts them for one minute. Concurrent writes exceed the container's 400-RU/s limit and produce rate-limited responses.

The Python client allows one retry before a remaining 429 reaches your code. This setting makes throttling easier to observe in the exercise; it isn't the default production retry setting.

1. In the same terminal, create a project folder and a virtual environment.

    ```powershell
    mkdir throttle-lab-python
    Set-Location throttle-lab-python
    python -m venv .venv
    .venv\Scripts\activate
    ```

1. Install the packages the script needs.

    ```powershell
    python -m pip install azure-cosmos==4.16.3 azure-identity==1.25.3
    ```

1. Create **throttle.py** in your project folder and paste the following code. The endpoint is passed when you run it, so you don't need to edit the code.

    ```python
    import argparse
    import time
    from concurrent.futures import ThreadPoolExecutor
    from dataclasses import dataclass
    from datetime import datetime, timezone

    from azure.cosmos import CosmosClient, exceptions
    from azure.identity import DefaultAzureCredential


    @dataclass
    class RequestResult:
        throttled: bool
        elapsed_ms: float
        activity_id: str
        retry_after_ms: str


    def run_workload(endpoint: str) -> None:
        with DefaultAzureCredential() as credential, CosmosClient(
            endpoint,
            credential=credential,
            retry_throttle_total=1,
        ) as client:
            container = client.get_database_client("cosmicworks").get_container_client("product")
            products = list(container.read_all_items())
            if not products:
                raise RuntimeError("The product container is empty. Complete setup with seeding enabled.")
            print(f"Read {len(products)} products.")

            def upsert(item: dict[str, object]) -> RequestResult:
                started = time.perf_counter()
                try:
                    response = container.upsert_item(item)
                    headers = response.get_response_headers()
                    return RequestResult(
                        False,
                        (time.perf_counter() - started) * 1000,
                        headers.get("x-ms-activity-id", "not returned"),
                        "not applicable",
                    )
                except exceptions.CosmosHttpResponseError as error:
                    if error.status_code != 429:
                        raise
                    return RequestResult(
                        True,
                        (time.perf_counter() - started) * 1000,
                        error.headers.get("x-ms-activity-id", "not returned"),
                        error.headers.get("x-ms-retry-after-ms", "not returned"),
                    )

            succeeded = 0
            throttled = 0
            successful_sample = None
            throttled_sample = None
            print(f"Workload start (UTC): {datetime.now(timezone.utc).isoformat()}")
            deadline = time.perf_counter() + 60

            # Aggregate results here; worker threads only issue requests.
            with ThreadPoolExecutor(max_workers=16) as pool:
                while time.perf_counter() < deadline:
                    for result in pool.map(upsert, products):
                        if result.throttled:
                            throttled += 1
                            if throttled_sample is None:
                                throttled_sample = result
                        else:
                            succeeded += 1
                            if successful_sample is None:
                                successful_sample = result

            print(f"Workload end (UTC): {datetime.now(timezone.utc).isoformat()}")
            print(f"Succeeded: {succeeded}")
            print(f"Rate limited (429): {throttled}")
            if successful_sample is not None:
                print(f"Sample successful upsert client elapsed: {successful_sample.elapsed_ms:.1f} ms")
            if throttled_sample is not None:
                print(f"Sample 429 client elapsed: {throttled_sample.elapsed_ms:.1f} ms")
                print(f"Retry after: {throttled_sample.retry_after_ms} ms")
                print(f"Activity ID of a rate-limited request: {throttled_sample.activity_id}")
            else:
                print("No application-visible 429s. Check the account, 400 RU/s setting, and service metrics.")


    def main() -> None:
        parser = argparse.ArgumentParser(description="Generate a one-minute load on the lab product container.")
        parser.add_argument("--endpoint", required=True, help="Endpoint of the disposable lab account.")
        args = parser.parse_args()
        run_workload(args.endpoint)


    if __name__ == "__main__":
        main()
    ```

1. Find `retry_throttle_total=1`, the 16-worker pool, and the exception check that handles only status `429`. Notice that other failures aren't counted as throttling. The application prints a client-measured elapsed time and retry-after header for a sample rate-limited request.

1. Run the script. It takes about a minute plus the time to read the container.

    ```powershell
    python throttle.py --endpoint $endpoint
    ```

    ```output
    Read 295 products.
    Workload start (UTC): 2026-10-20T12:00:00+00:00
    Workload end (UTC): 2026-10-20T12:01:02+00:00
    Succeeded: 2765
    Rate limited (429): 1102
    Sample successful upsert client elapsed: 24.5 ms
    Sample 429 client elapsed: 135.2 ms
    Retry after: 100 ms
    Activity ID of a rate-limited request: 4f2c8b1e-6a3d-4c05-9f7b-1d2e3a4b5c6d
    ```

1. Record your UTC workload window, rate-limited count, sample client elapsed times, and activity ID.

    Your counts and timings will differ from the example. If no 429 reaches your code, confirm that you used the 400-RU/s lab account and check the service metrics in Task 3.

1. Return to the shared folder for subsequent CLI commands.

    ```powershell
    Set-Location ..
    ```

## Task 3: Investigate throttling, latency, and partition utilization

Use Azure Monitor metrics to compare the client's results with the requests recorded by the service.

1. In a browser, open the [Azure portal](https://portal.azure.com) and go to the Azure Cosmos DB account this exercise created.

1. In the resource menu, under **Monitoring**, select **Insights**.

1. Select the **Requests** tab and find the **Total Requests by Status Code** chart. Set the time range to the last hour and filter to the `cosmicworks` database and `product` container.

    Locate your recorded workload window and look for 429 responses alongside successful requests. Platform metrics can take a few minutes to appear. If the newest points aren't present, do Task 4 and check again before cleanup.

1. Select the **Throughput** tab and find the **Normalized RU Consumption (%) By PartitionKeyRangeID** chart.

    Filter to the same database and container. Look for utilization near 100 percent during the workload. A new, small 400-RU/s container is expected to have one physical partition; check how many ranges are actually shown. One range can't demonstrate skew between physical partitions. In a larger container, one saturated range while others idle suggests skew; all ranges saturated suggests broader capacity pressure. A brief 100-percent peak alone doesn't establish a problem.

1. In the account's resource menu, under **Monitoring**, select **Metrics**.

1. Confirm **Scope** is the account created for this exercise. In **Metric namespace**, choose the Cosmos DB standard metrics namespace. In **Metric**, select **Total Requests**, then set **Aggregation** to **Count**.

1. Set the time range to **Last hour** and select **Apply**. Select **Apply splitting**, then choose the `StatusCode` dimension.

    The split chart separates the status codes present in the selected window. Successful upserts of the existing products return 200; an upsert returns 201 only when it creates an item. Compare the 429 count here with the count your application reported.

    The service counts every rate-limited attempt, including those the SDK retries. Your application counts only operations that still fail after the permitted retry, so its count can be lower. Compare counts from the same workload window.

1. Select **New chart** and use the same scope and metric namespace. Choose **Server Side Latency Gateway** with **Avg** aggregation. Python uses gateway connectivity. Filter to the `cosmicworks` database and `product` container and, for an upsert comparison, the `Upsert` operation type.

    Compare the chart during your workload window with the sample client elapsed times. The chart measures server processing; client timing also includes network transit and SDK retry waits. Because the chart aggregates many requests and the application reports individual samples, the difference isn't an exact measure of network latency.

1. Record a short finding: which status code indicates throttling, what the utilization chart supports, and why client elapsed time can exceed server-side latency. Choose an alert threshold for a real application against expected traffic and acceptable latency rather than copying this lab's threshold.

## Task 4: Investigate a synthetic incident with KQL

Use KQL to investigate synthetic diagnostic records. The `datatable` operator defines the sample data within the query; it doesn't read your account's logs.

1. In the search bar at the top of the Azure portal, enter **Log Analytics workspaces**. Under **Services**, select **Log Analytics workspaces**.

1. On the workspace list, select **dp420lab14-logs** in the resource group you used in Task 1. You are opening the workspace resource, not the Azure Cosmos DB account.

1. In the workspace's resource menu, select **Logs**. Close the queries dialog if it opens.

    > **Note**: You might need to turn off **Agent mode** and select **KQL mode** in the upper-right corner of the Logs pane to display the query editor.

1. Create a new query in the workspace's Logs pane and paste the following code. Select all the query text and select **Run** so both table declarations and the investigation pipeline execute together.

    ```kusto
    // Synthetic teaching data, not telemetry from your account or a complete workload.
    let IncidentStart = bin(now(), 1m) - 5m;
    let SampleRequests = datatable(
        OffsetSeconds:long, ActivityId:string, OperationName:string,
        StatusCode:int, RequestCharge:real, DurationMs:real)
    [
        0, "11111111-1111-4111-8111-111111111101", "Upsert", 200, 7.0, 2.1,
        0, "11111111-1111-4111-8111-111111111102", "Upsert", 200, 7.0, 2.4,
        0, "11111111-1111-4111-8111-111111111103", "Upsert", 200, 7.0, 2.0,
        1, "11111111-1111-4111-8111-111111111104", "Upsert", 200, 7.0, 2.6,
        1, "11111111-1111-4111-8111-111111111105", "Upsert", 429, 0.0, 0.3,
        1, "11111111-1111-4111-8111-111111111106", "Upsert", 429, 0.0, 0.4,
        1, "11111111-1111-4111-8111-111111111107", "Upsert", 200, 7.0, 2.3,
        2, "11111111-1111-4111-8111-111111111108", "Upsert", 200, 7.0, 2.2,
        2, "11111111-1111-4111-8111-111111111109", "Upsert", 429, 0.0, 0.3,
        2, "11111111-1111-4111-8111-111111111110", "Upsert", 429, 0.0, 0.5,
        0, "11111111-1111-4111-8111-111111111111", "Read",   200, 1.0, 1.0,
        1, "11111111-1111-4111-8111-111111111112", "Read",   200, 1.0, 1.2,
        1, "11111111-1111-4111-8111-111111111113", "Read",   200, 1.0, 1.1,
        2, "11111111-1111-4111-8111-111111111114", "Read",   200, 1.0, 1.3
    ]
    | extend TimeGenerated = IncidentStart + OffsetSeconds * 1s
    | project-away OffsetSeconds;
    let SamplePartitionRU = datatable(OffsetSeconds:long, PartitionKey:string, RequestCharge:real)
    [
        0, "bikes",       15.0,
        0, "components",   7.0,
        1, "bikes",       14.0,
        1, "components",   1.0,
        1, "accessories",  1.0,
        2, "bikes",        7.0,
        2, "accessories",  1.0
    ]
    | extend TimeGenerated = IncidentStart + OffsetSeconds * 1s
    | project-away OffsetSeconds;
    // Investigation query: keep all declarations above when replacing this pipeline.
    SampleRequests
    | summarize Requests = count(),
                ThrottledRequests = countif(StatusCode == 429),
                TotalRU = sum(RequestCharge)
        by OperationName
    | extend RateLimitedPercent = round(100.0 * ThrottledRequests / Requests, 1)
    | order by RateLimitedPercent desc
    ```

    `SampleRequests` models selected fields from `CDBDataPlaneRequests`; `SamplePartitionRU` models per-key, per-second charges from `CDBPartitionKeyRUConsumption`. Both tables exist only within this query.

    The first result should be:

    | OperationName | Requests | ThrottledRequests | TotalRU | RateLimitedPercent |
    | :--- | ---: | ---: | ---: | ---: |
    | Upsert | 10 | 4 | 42 | 40 |
    | Read | 4 | 0 | 4 | 0 |

    Only upserts are rate limited in this sample. Identify the condition in the query that distinguishes throttled requests from successful requests.

1. Keep all declarations above the `// Investigation query` comment. Replace only the final `SampleRequests` pipeline with the following query, then select all the text and run it:

    ```kusto
    SamplePartitionRU
    | summarize TotalRU = sum(RequestCharge) by PartitionKey
    | order by TotalRU desc
    ```

    Expect `bikes` at **36 RU**, `components` at **8 RU**, and `accessories` at **2 RU**. The charges total 46 RU, matching the first query. The `bikes` key consumes most of the sample's request units. Before concluding that a key is causing throttling, check physical-partition utilization over a representative workload window.

1. A **synthetic client error** for this incident reports status `429` and activity ID `11111111-1111-4111-8111-111111111105`. Keeping the declarations, replace the final pipeline with:

    ```kusto
    SampleRequests
    | where ActivityId == "11111111-1111-4111-8111-111111111105"
    | project TimeGenerated, OperationName, StatusCode, RequestCharge, DurationMs
    ```

    Expect one `Upsert` row with status `429`, charge **0 RU**, and duration **0.3 ms**. The activity ID links the sample client error to its matching request record.

## Clean up resources

This exercise creates an Azure Cosmos DB account, a Log Analytics workspace, an alert rule, and an action group. Remove the resources you created when you finish. Provisioned throughput remains billable even without requests, and Log Analytics can charge for data ingestion and retention.

Delete the diagnostic setting before deleting the account. Otherwise, a resource later created with the same name could inherit the setting.

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

You generated throttling, compared client and service metrics, configured a metric alert, and used KQL to investigate synthetic diagnostic records.
