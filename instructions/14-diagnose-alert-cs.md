---
lab:
  title: Diagnose throttling and configure an alert in C#
  module: Module 14 - Monitor and Troubleshoot Azure Cosmos DB
  description: Generate real throttling, investigate client diagnostics and live metrics, configure a metric alert, and practice KQL with synthetic incident records without waiting for log ingestion.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Diagnose throttling and configure an alert in C#

In this exercise, you generate real rate limiting on an Azure Cosmos DB account, investigate client diagnostics and Azure Monitor metrics, and configure an alert for future incidents. You also use Kusto Query Language (KQL) to investigate a supplied synthetic incident, including a request identified by its activity ID.

The client output, metrics, and alert use your own account. The required KQL investigation uses clearly labeled sample records defined in the query itself, not telemetry from your account. You configure diagnostic logging, but **don't wait for live logs or an alert email** to complete the exercise.

This exercise takes approximately **45** minutes to complete.

Plan for 10 minutes of setup, 8 minutes to configure monitoring, 6 minutes to create and run the workload project, 7 minutes for metrics, 8 minutes for KQL, and 3 minutes for cleanup, leaving 3 minutes of buffer. Copy the code blocks rather than typing the workload from scratch. Azure provisioning times can vary.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

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

The container uses manual throughput rather than autoscale on purpose. A fixed 400-RU/s ceiling makes rate limiting easier to reproduce within the lab time budget. Autoscale can absorb more load up to its configured maximum, but requests that exceed that maximum are still rate limited.

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. The examples authenticate with Microsoft Entra ID through `DefaultAzureCredential`. This credential can use your `az login` session, but it checks other credential sources first. Make sure the identity it selects has the data-plane role assignment.

> &#9888; Use only the account this script creates for this exercise. Later steps attach a diagnostic setting and an alert rule. Never point this exercise at a shared training or production account.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Configure diagnostic logging and a metric alert

Platform metrics are collected automatically; diagnostic logs are opt-in. Configure both the log destination and a real metric alert before generating load. The alert uses platform metrics, so it doesn't depend on Log Analytics ingestion.

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

    The `@<file>` argument avoids PowerShell's inline JSON quoting issues. Resource-specific mode sends the categories to `CDBDataPlaneRequests` and `CDBPartitionKeyRUConsumption`, rather than the legacy `AzureDiagnostics` table. Request logs can incur ingestion and retention charges.

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

    This confirms configuration, not that delivery has started. Initial log delivery can exceed the lab time budget. The required investigation in Task 4 doesn't depend on it.

1. Create an action group and capture its resource ID. Replace the email address with your own. You might receive an action-group notification or verification message; don't wait for it to continue.

    ```powershell
    $actionGroupId = az monitor action-group create `
        --name "dp420lab14-oncall" `
        --resource-group $resourceGroup `
        --short-name "dp420lab14" `
        --action email oncall you@contoso.com `
        --query id --output tsv
    ```

1. Create a metric alert scoped to the account. It counts **Total Requests** filtered to a `StatusCode` of `429`, not all requests or the number of request units.

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

    The rule can take about 10 minutes to become active. Continue with the workload while it activates. Creating and verifying the rule is required; an alert firing or an email arriving isn't. A threshold of 100 is for this deliberate lab load, not a production recommendation.

## Task 2: Drive the container into rate limiting

Now you generate the incident. The application reads every product in the container and upserts each one back, repeatedly, for one minute. At 400 RU/s, that workload asks for far more throughput than the container has.

The .NET client disables automatic retries on rate limiting. This setting makes throttling easier to observe in the exercise; it isn't the default production retry setting.

1. In the same terminal, create a project folder and a console application.

    ```powershell
    mkdir throttle-lab-cs
    Set-Location throttle-lab-cs
    dotnet new console --framework net10.0
    ```

1. Add the Cosmos DB SDK, `Azure.Identity`, and the explicit `Newtonsoft.Json` reference the Cosmos DB SDK requires.

    ```powershell
    dotnet add package Microsoft.Azure.Cosmos --version 3.63.0
    dotnet add package Azure.Identity --version 1.21.0
    dotnet add package Newtonsoft.Json --version 13.0.4
    ```

1. Replace **Program.cs** in your project with the following code. The endpoint is passed when you run it, so you don't need to edit the code.

    ```csharp
    using System.Diagnostics;
    using System.Net;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;
    using Newtonsoft.Json.Linq;

    if (args.Length != 1 || !Uri.TryCreate(args[0], UriKind.Absolute, out Uri? endpoint) ||
        endpoint.Scheme != Uri.UriSchemeHttps)
    {
        throw new ArgumentException("Usage: dotnet run -- <https-cosmos-endpoint>");
    }

    using CosmosClient client = new(
        accountEndpoint: endpoint.AbsoluteUri,
        tokenCredential: new DefaultAzureCredential(),
        clientOptions: new CosmosClientOptions
        {
            ConnectionMode = ConnectionMode.Direct,
            MaxRetryAttemptsOnRateLimitedRequests = 0
        });

    Container container = client.GetContainer("cosmicworks", "product");
    List<JObject> products = new();
    using (FeedIterator<JObject> iterator = container.GetItemQueryIterator<JObject>("SELECT * FROM c"))
    {
        while (iterator.HasMoreResults)
        {
            products.AddRange(await iterator.ReadNextAsync());
        }
    }
    if (products.Count == 0)
    {
        throw new InvalidOperationException("The product container is empty. Complete setup with seeding enabled.");
    }
    Console.WriteLine($"Read {products.Count} products.");

    int succeeded = 0;
    int throttled = 0;
    object resultLock = new();
    RequestSample? successfulSample = null;
    RequestSample? throttledSample = null;
    Console.WriteLine($"Workload start (UTC): {DateTimeOffset.UtcNow:O}");
    Stopwatch workload = Stopwatch.StartNew();

    while (workload.Elapsed < TimeSpan.FromSeconds(60))
    {
        await Parallel.ForEachAsync(
            products,
            new ParallelOptions { MaxDegreeOfParallelism = 32 },
            async (product, cancellationToken) =>
            {
                string categoryId = product.Value<string>("categoryId")
                    ?? throw new InvalidOperationException("A seeded product is missing categoryId.");
                Stopwatch request = Stopwatch.StartNew();
                try
                {
                    ItemResponse<JObject> response = await container.UpsertItemAsync(
                        product, new PartitionKey(categoryId), cancellationToken: cancellationToken);
                    lock (resultLock)
                    {
                        succeeded++;
                        successfulSample ??= new(request.Elapsed.TotalMilliseconds, response.ActivityId, null);
                    }
                }
                catch (CosmosException error) when (error.StatusCode == HttpStatusCode.TooManyRequests)
                {
                    lock (resultLock)
                    {
                        throttled++;
                        throttledSample ??= new(
                            request.Elapsed.TotalMilliseconds, error.ActivityId, error.RetryAfter?.TotalMilliseconds);
                    }
                }
            });
    }

    Console.WriteLine($"Workload end (UTC): {DateTimeOffset.UtcNow:O}");
    Console.WriteLine($"Succeeded: {succeeded}");
    Console.WriteLine($"Rate limited (429): {throttled}");
    if (successfulSample is not null)
    {
        Console.WriteLine($"Sample successful upsert client elapsed: {successfulSample.ElapsedMs:F1} ms");
    }
    if (throttledSample is not null)
    {
        Console.WriteLine($"Sample 429 client elapsed: {throttledSample.ElapsedMs:F1} ms");
        string retryAfter = throttledSample.RetryAfterMs is double milliseconds
            ? $"{milliseconds:F1} ms" : "not returned";
        Console.WriteLine($"Retry after: {retryAfter}");
        Console.WriteLine($"Activity ID of a rate-limited request: {throttledSample.ActivityId}");
    }
    else
    {
        Console.WriteLine("No application-visible 429s. Check the account, 400 RU/s setting, and service metrics.");
    }

    record RequestSample(double ElapsedMs, string ActivityId, double? RetryAfterMs);
    ```

1. Find `MaxRetryAttemptsOnRateLimitedRequests = 0`, the 32-worker limit, and the exception filter that handles only `TooManyRequests`. Notice that other failures aren't counted as throttling. The application prints a client-measured elapsed time and retry-after value for a sample rate-limited request.

1. Run the application. It takes about a minute plus the time to read the container.

    ```powershell
    dotnet run --no-restore -- $endpoint
    ```

    ```output
    Read 295 products.
    Workload start (UTC): 2026-10-20T12:00:00+00:00
    Workload end (UTC): 2026-10-20T12:01:02+00:00
    Succeeded: 3184
    Rate limited (429): 9260
    Sample successful upsert client elapsed: 12.5 ms
    Sample 429 client elapsed: 14.2 ms
    Retry after: 100.0 ms
    Activity ID of a rate-limited request: 4f2c8b1e-6a3d-4c05-9f7b-1d2e3a4b5c6d
    ```

1. Record your UTC workload window, rate-limited count, sample client elapsed times, and activity ID. These are from your account, unlike the synthetic records in Task 4.

    The output above is illustrative. Your counts and timings depend on region, item size, and client concurrency. The run takes about a minute plus catalog reads and in-flight requests. If no 429 reaches your code, verify that you targeted the disposable 400-RU/s account and inspect the service metrics; don't invent a count or repeatedly rerun the workload to wait for logs.

1. Return to the shared folder for subsequent CLI commands.

    ```powershell
    Set-Location ..
    ```

## Task 3: Investigate throttling, latency, and partition utilization

The client saw its own failures. Now confirm the same event from the service's side, where the count includes every rate-limited response rather than only the ones that reached your code.

1. In a browser, open the [Azure portal](https://portal.azure.com) and go to the Azure Cosmos DB account this exercise created.

1. In the resource menu, under **Monitoring**, select **Insights**.

1. Select the **Requests** tab and find the **Total Requests by Status Code** chart. Set the time range to the last hour and filter to the `cosmicworks` database and `product` container.

    Locate your recorded workload window and look for 429 responses alongside successful requests. Platform metrics can take a few minutes to appear. If the newest points aren't present, do Task 4 and check once more before cleanup; don't wait for diagnostic logs.

1. Select the **Throughput** tab and find the **Normalized RU Consumption (%) By PartitionKeyRangeID** chart.

    Filter to the same database and container. Look for utilization near 100 percent during the workload. A new, small 400-RU/s container is expected to have one physical partition; check how many ranges are actually shown. One range can't demonstrate skew between physical partitions. In a larger container, one saturated range while others idle suggests skew; all ranges saturated suggests broader capacity pressure. A brief 100-percent peak alone doesn't establish a problem.

1. In the account's resource menu, under **Monitoring**, select **Metrics**.

1. Confirm **Scope** is the account created for this exercise. In **Metric namespace**, choose the Cosmos DB standard metrics namespace. In **Metric**, select **Total Requests**, then set **Aggregation** to **Count**.

1. Set the time range to **Last hour** and select **Apply**. Select **Apply splitting**, then choose the `StatusCode` dimension.

    The split chart separates the status codes present in the selected window. Successful upserts of the existing products return 200; an upsert returns 201 only when it creates an item. Compare the 429 count here with the count your application reported.

    The two numbers are close for the same workload window because you disabled automatic 429 retries. With the default retries, some rate-limited attempts succeed on retry and never become application errors. Rerunning this timed workload can also change the request volume and the service's 429 count, so compare each run within its own time window.

1. Select **New chart** and use the same scope and metric namespace. Choose **Server Side Latency Direct** with **Avg** aggregation. Your C# application explicitly uses direct connectivity. Filter to the `cosmicworks` database and `product` container and, for an upsert comparison, the `Upsert` operation type.

    Compare the chart during your workload window with the sample client elapsed times. The chart measures server processing; the client timing also includes network transit and, with normal SDK settings, retry waits. This application's 429 retries are disabled. A single client sample and an aggregated metric aren't identical measurements, so don't subtract them to calculate exact network latency or treat a difference as proof of a service fault.

1. Record a short finding: which status code indicates throttling, what the utilization chart supports, and why client elapsed time can exceed server-side latency. Choose an alert threshold for a real application against expected traffic and acceptable latency rather than copying this lab's threshold.

## Task 4: Investigate a synthetic incident with KQL

This required task uses synthetic teaching data, not logs captured from your workload. The `datatable` operator defines rows inside the query, so you can run the investigation immediately even if your account's diagnostic tables don't exist yet.

1. In the Azure portal, open the **dp420lab14-logs** Log Analytics workspace you created, then select **Logs**. Close the queries dialog if it opens.

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

    `SampleRequests` models selected fields from `CDBDataPlaneRequests`; `SamplePartitionRU` models per-key, per-second charges from `CDBPartitionKeyRUConsumption`. They are query-local tables, not workspace tables, and nothing is ingested. Their timestamps are generated relative to query execution to keep the sample in a recent time range.

    The first result should be:

    | OperationName | Requests | ThrottledRequests | TotalRU | RateLimitedPercent |
    | :--- | ---: | ---: | ---: | ---: |
    | Upsert | 10 | 4 | 42 | 40 |
    | Read | 4 | 0 | 4 | 0 |

    Explain why the status-code filter matters: only upserts are rate limited in this sample. These small records are an illustrative subset, not enough evidence to measure the account's full workload or diagnose every cause of 429.

1. Keep all declarations above the `// Investigation query` comment. Replace only the final `SampleRequests` pipeline with the following query, then select all the text and run it:

    ```kusto
    SamplePartitionRU
    | summarize TotalRU = sum(RequestCharge) by PartitionKey
    | order by TotalRU desc
    ```

    Expect `bikes` at **36 RU**, `components` at **8 RU**, and `accessories` at **2 RU**. The charges total 46 RU, matching the first query. `bikes` dominates this subset; that suggests a question about skew, not proof of a hot physical partition. Use the physical-partition utilization pattern and a representative workload window before choosing between more throughput and a partition-key change.

1. A **synthetic client error** for this incident reports status `429` and activity ID `11111111-1111-4111-8111-111111111105`. Keeping the declarations, replace the final pipeline with:

    ```kusto
    SampleRequests
    | where ActivityId == "11111111-1111-4111-8111-111111111105"
    | project TimeGenerated, OperationName, StatusCode, RequestCharge, DurationMs
    ```

    Expect one `Upsert` row with status `429`, charge **0 RU**, and duration **0.3 ms**. You correlated a supplied client error with its supplied request record. Don't substitute your own activity ID here: your workload didn't create these sample rows.

### Optional: Inspect your account's live logs

Only if time remains, run this separate query in the workspace. These are real diagnostic records, unlike the required sample investigation:

```kusto
CDBDataPlaneRequests
| where TimeGenerated >= ago(2h)
| where DatabaseName == "cosmicworks" and CollectionName == "product"
| summarize Requests = count() by AccountName, StatusCode
```

If no records are returned or the table doesn't exist yet, skip this extension. Don't wait or rerun the workload. If records are present, insert an `ActivityId` filter using your own recorded ID before `summarize` to try request correlation. Missing live logs or an unmatched ID doesn't prevent completion.

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

You generated and investigated live throttling, compared client and server-side signals, configured a real metric alert, and practiced request-level investigation with synthetic diagnostic records. You completed the required work without depending on live log delivery or an alert notification.
