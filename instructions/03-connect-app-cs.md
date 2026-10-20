---
lab:
  title: Connect an app to Azure Cosmos DB in C#
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

# Connect an app to Azure Cosmos DB in C#

In this exercise, you connect an SDK application to the local Azure Cosmos DB emulator, add logging and error handling, and then connect the same application to a cloud account with Microsoft Entra authentication.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need the [.NET 10 SDK](https://dotnet.microsoft.com/download) or later installed.

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

1. Open a terminal and create a new console project:

    ```bash
    dotnet new console -n cosmos-connect-exercise
    cd cosmos-connect-exercise
    ```

1. Add the Azure Cosmos DB SDK, the Newtonsoft.Json dependency it requires, and the Azure Identity library:

    ```bash
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Newtonsoft.Json --version 13.0.4
    dotnet add package Azure.Identity
    ```

1. Open **Program.cs** and replace its contents with the following using directives:

    ```csharp
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;
    using Microsoft.Azure.Cosmos.Fluent;
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

1. In **Program.cs**, below the using directives, add the emulator connection constants and client initialization:

    ```csharp
    string endpoint = "https://localhost:8081/";
    string key = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // ==== CLIENT ==== Task 4 replaces this section. Task 6 replaces it again.
    // Emulator-only certificate bypass; use Gateway mode for this local client.
    CosmosClientOptions options = new()
    {
        HttpClientFactory = () =>
        {
            var handler = new System.Net.Http.HttpClientHandler
            {
                ServerCertificateCustomValidationCallback =
                    System.Net.Http.HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
            };
            return new System.Net.Http.HttpClient(handler);
        },
        ConnectionMode = ConnectionMode.Gateway
    };

    CosmosClient client = new(endpoint, key, options);
    // ==== END CLIENT ====
    ```

    > &#9888; `DangerousAcceptAnyServerCertificateValidator` disables SSL certificate validation. ***Use this setting only for the local emulator; never use it in production code***. Alternatively, import the emulator certificate as described in [Import the emulator's TLS/SSL certificate](/azure/cosmos-db/how-to-develop-emulator#import-the-emulators-tlsssl-certificate) and omit the custom `HttpClientFactory`.

1. To verify the connection, read account properties. These lines stay in the file for the whole exercise:

    ```csharp
    // Read account metadata from the service, not an item in a container.
    AccountProperties account = await client.ReadAccountAsync();
    Console.WriteLine($"Account name:     {account.Id}");
    Console.WriteLine($"Primary region:   {account.WritableRegions.FirstOrDefault()?.Name}");
    Console.WriteLine($"Consistency:      {account.Consistency.DefaultConsistencyLevel}");
    ```

1. Run the project:

    ```bash
    dotnet run
    ```

1. Verify that the output shows the emulator account name (typically **localhost**), the primary region, and the consistency level.

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

1. Below the account output, add the following code to reference the database and container:

    ```csharp
    // These calls build references; ReadContainerAsync makes the service request.
    Database database = client.GetDatabase("cosmicworks");
    Container container = client.GetContainer("cosmicworks", "product");

    ContainerProperties properties = await container.ReadContainerAsync();

    Console.WriteLine($"Database:         {database.Id}");
    Console.WriteLine($"Container:        {properties.Id}");
    ```

    The container read confirms that the resource exists and that the application can access it.

1. Run the project again and confirm both names appear in the output.

---

## Task 4: Add a logging handler

Add a custom SDK request handler that logs request methods, URIs, status codes, and RU charges.

1. At the **bottom** of **Program.cs**, after all top-level statements, add the following class definition:

    ```csharp
    public class LogHandler : RequestHandler
    {
        public override async Task<ResponseMessage> SendAsync(
            RequestMessage request, CancellationToken cancellationToken)
        {
            Console.WriteLine($"  [REQ]  {request.Method.Method} {request.RequestUri}");
            // Forward the request through the SDK pipeline.
            ResponseMessage response = await base.SendAsync(request, cancellationToken);
            Console.WriteLine($"  [RES]  {(int)response.StatusCode} {response.StatusCode}" +
                              $"  RU: {response.Headers.RequestCharge:0.00}");
            return response;
        }
    }
    ```

1. Replace the marked client section with the following code:

    ```csharp
    // ==== CLIENT ==== Task 6 replaces this section.
    // Keep the emulator-only transport settings while adding the logging handler.
    CosmosClient client = new CosmosClientBuilder(endpoint, key)
        .WithConnectionModeGateway()
        .WithHttpClientFactory(() =>
        {
            var handler = new System.Net.Http.HttpClientHandler
            {
                ServerCertificateCustomValidationCallback =
                    System.Net.Http.HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
            };
            return new System.Net.Http.HttpClient(handler);
        })
        .AddCustomHandlers(new LogHandler())
        .Build();
    // ==== END CLIENT ====
    ```

    Leave the `endpoint` and `key` lines above the marker alone.

1. Run the project again and inspect the method, URI, status code, and RU charge logged by the handler.

---

## Task 5: Handle a missing-item error

Read a nonexistent item and inspect the SDK exception and status code.

1. Below the two `Console.WriteLine` lines that print the database and container names, add a `try/catch` block that attempts to read a nonexistent item:

    ```csharp
    try
    {
        // A nonexistent ID and partition key deliberately exercise error handling.
        var response = await container.ReadItemAsync<dynamic>(
            id: "nonexistent-id",
            partitionKey: new PartitionKey("nonexistent-category"));
    }
    catch (CosmosException ex)
    {
        // Inspect the exception's status code.
        Console.WriteLine($"\nCaught CosmosException:");
        Console.WriteLine($"  Status code:    {(int)ex.StatusCode} ({ex.StatusCode})");
        Console.WriteLine($"  Is retryable:   " +
            $"{ex.StatusCode == System.Net.HttpStatusCode.TooManyRequests ||
               ex.StatusCode == System.Net.HttpStatusCode.ServiceUnavailable}");
    }
    ```

1. Run the project. Confirm that the output shows **404 Not Found** and that `Is retryable` is `False`.

---

## Task 6: Point the app at the cloud account

Connect the application to the cloud account using `AzureCliCredential` and your Azure CLI sign-in. Keep the existing account read, container access, logging, and error handling.

1. Point `endpoint` at the account the setup script printed, and delete the `key` line. Key-based authentication is disabled for this account:

    ```csharp
    string endpoint = "<cosmos-endpoint>";
    ```

1. Replace everything between the `// ==== CLIENT ====` markers with the following code:

    ```csharp
    // ==== CLIENT ====
    // Explicitly use az login and normal certificate validation for the cloud account.
    // Retain the logging handler while removing the emulator's transport overrides.
    CosmosClient client = new CosmosClientBuilder(endpoint, new AzureCliCredential())
        .AddCustomHandlers(new LogHandler())
        .Build();
    // ==== END CLIENT ====
    ```

    The cloud client uses normal certificate validation and the default Direct connection mode. Ensure the required outbound ports are allowed. The logging handler remains enabled.

1. Run the project:

    ```bash
    dotnet run
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
