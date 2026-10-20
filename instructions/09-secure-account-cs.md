---
lab:
  title: Secure an account in C#
  module: Module 9 - Secure an Azure Cosmos DB Solution
  description: Secure an Azure Cosmos DB for NoSQL account with Microsoft Entra authentication, a managed identity, scoped data-plane roles, and network access restrictions.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Secure an account in C#

In this exercise, you host a product reader in Azure Container Instances (ACI), authenticate with a system-assigned managed identity, and test read-only access and network restrictions. Your local Azure CLI identity manages resources; the hosted identity accesses data.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

The application runs inside the container, so you don't need to install the .NET SDK locally.

This exercise also requires:

- Azure **Contributor** access to the resources in the resource group you use.
- Registered `Microsoft.DocumentDB` and `Microsoft.ContainerInstance` resource providers, or permission to register them at subscription scope. See [Azure resource providers and types](/azure/azure-resource-manager/management/resource-providers-and-types).
- A region, such as `eastus`, that supports Azure Cosmos DB serverless and Linux [Azure Container Instances](/azure/container-instances/container-instances-region-availability), with quota for 2 CPUs and 4 GB of memory. The container needs outbound access to Azure Cosmos DB, the managed identity endpoint, GitHub, and package repositories.

Charges include ACI uptime and Azure Cosmos DB serverless request units (RUs) and storage. Complete the cleanup task even after a failure.

## Set up your Azure Cosmos DB resources

This exercise creates a separate Azure Cosmos DB account. Delete this account at the end of the exercise.

> &#9888; Use only the account this script creates for this exercise. The network test deliberately blocks all public data access to that account. Never point this exercise at a shared training or production account.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**. Keep this **local PowerShell** session open for the whole exercise: its variables stay available after you exit the container shell.

1. Sign in to the Azure CLI and confirm the subscription you're working in. Follow the sign-in prompts for your environment. Select the intended subscription if prompted.

    ```azurecli
    az login
    az account show --query '{Subscription:name,Id:id}' --output table
    ```

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "eastus"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab09 -LabProfile security
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab09a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set variables for the account and the container group so the commands in this exercise can use them.

    ```powershell
    $account = "<your-account-name>"
    $containerGroupName = "security-client"
    $endpoint = az cosmosdb show --resource-group $resourceGroup --name $account `
        --query documentEndpoint --output tsv
    ```

1. Confirm the security baseline. Expect **LocalAuthDisabled** to be **True** and **PublicAccess** to be **Enabled**.

    ```azurecli
    az cosmosdb show --resource-group $resourceGroup --name $account `
        --query '{LocalAuthDisabled:disableLocalAuth,PublicAccess:publicNetworkAccess}' --output table
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, serverless, with key-based authentication disabled and public network access enabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, serverless, and initially empty |

The setup script grants no data-plane role to your local Azure CLI identity. You assign data-plane permissions to the hosted managed identity in Task 2.

## Task 1: Write the managed identity client

The client downloads and caches 295 CosmicWorks products inside the container. Each test uses the first product's item ID and partition key.

The client has three modes: `seed` loads the catalog, `read` performs a point read, and `check` verifies that reading succeeds while replacement is denied with HTTP 403.

1. In **local PowerShell**, create a `dp420-security` subfolder under the current **Allfiles/Labs/Shared** folder and change to it.

    ```powershell
    $workFolder = Join-Path $PWD.Path 'dp420-security'
    New-Item -ItemType Directory -Path $workFolder -Force | Out-Null
    Set-Location $workFolder
    ```

1. In the **dp420-security** folder, create `Program.cs` in Visual Studio Code with the following code.

    ```csharp
    using System;
    using System.IO;
    using System.Linq;
    using System.Net;
    using System.Net.Http;
    using Azure.Identity;
    using Microsoft.Azure.Cosmos;
    using Newtonsoft.Json.Linq;

    // Exit codes: 0 = expected result, 1 = unexpected result,
    // 2 = invalid arguments or configuration, 3 = seed or read denied.
    if (args.Length != 1 || args[0] is not ("seed" or "read" or "check"))
    {
        Console.WriteLine("Usage: seed | read | check");
        return 2;
    }

    string mode = args[0];
    try
    {
        string? endpoint = Environment.GetEnvironmentVariable("COSMOS_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            Console.WriteLine("COSMOS_ENDPOINT is required.");
            return 2;
        }

        // Cache the catalog for reuse across test runs.
        const string sourceUrl = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product";
        const string cacheFile = "products.json";
        if (!File.Exists(cacheFile))
        {
            using HttpClient downloader = new HttpClient();
            await File.WriteAllTextAsync(cacheFile, await downloader.GetStringAsync(sourceUrl));
        }

        // Validate the catalog before accessing Cosmos DB.
        JArray products = JArray.Parse(await File.ReadAllTextAsync(cacheFile));
        if (products.Count != 295 || products.Any(product =>
            product is not JObject ||
            product["id"]?.Type != JTokenType.String ||
            product["categoryId"]?.Type != JTokenType.String))
        {
            throw new InvalidDataException();
        }

        // Use the same product and partition key for every test.
        JObject firstProduct = (JObject)products[0]!;
        string productId = firstProduct.Value<string>("id")!;
        string categoryId = firstProduct.Value<string>("categoryId")!;
        // Authenticate as the container's system-assigned managed identity.
        var credential = new ManagedIdentityCredential(ManagedIdentityId.SystemAssigned);
        // Use Gateway mode (HTTPS) for the network test.
        using CosmosClient client = new CosmosClient(endpoint, credential,
            new CosmosClientOptions { ConnectionMode = ConnectionMode.Gateway });
        Container container = client.GetContainer("cosmicworks", "product");

        if (mode == "seed")
        {
            foreach (JObject product in products.Cast<JObject>())
            {
                // Route each write using that product's partition key value.
                await container.UpsertItemAsync(product,
                    new PartitionKey(product.Value<string>("categoryId")!));
            }
            Console.WriteLine($"Seed succeeded: {products.Count} items.");
            return 0;
        }

        // Confirm read access before testing write denial.
        await container.ReadItemAsync<JObject>(productId, new PartitionKey(categoryId));
        Console.WriteLine("Read succeeded.");
        if (mode == "read")
        {
            return 0;
        }

        try
        {
            // Test write permission using the original product values.
            await container.ReplaceItemAsync(firstProduct, productId, new PartitionKey(categoryId));
            Console.WriteLine("UNEXPECTED: Write succeeded.");
            return 1;
        }
        catch (CosmosException exception) when (exception.StatusCode == HttpStatusCode.Forbidden)
        {
            // Only a 403 from replacement is an expected write denial.
            Console.WriteLine("Write denied (403). Expected.");
            return 0;
        }
    }
    catch (CosmosException exception) when (exception.StatusCode == HttpStatusCode.Forbidden)
    {
        // Return a distinct result when seeding or reading is denied.
        Console.WriteLine(mode == "seed" ? "Seed denied (403)." : "Read denied (403).");
        return 3;
    }
    catch (CosmosException exception)
    {
        Console.WriteLine($"Unexpected Cosmos status ({(int)exception.StatusCode}).");
        return 1;
    }
    catch (Exception exception)
    {
        // Report the error type without exposing request details.
        Console.WriteLine($"Unexpected failure ({exception.GetType().Name}).");
        return 1;
    }
    ```

1. Set the image and source filename in **local PowerShell**. Don't run the program locally: only the container exposes its managed identity.

    ```powershell
    $image = 'mcr.microsoft.com/dotnet/sdk:10.0'
    $sourceFile = 'Program.cs'
    ```

## Task 2: Host the client and load products

Temporarily grant Data Contributor to load the catalog, then replace it with Data Reader for the application. Use a separate loader identity in production.

### Create the host identity

1. Encode the source file in **local PowerShell** for transfer to the container. Base64 encoding doesn't encrypt the source.

    ```powershell
    $sourceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $sourceFile)))
    ```

1. Create an ACI container group with a system-assigned identity. Keep the container running for the following tests.

    ```azurecli
    az container create --resource-group $resourceGroup --name $containerGroupName `
        --location $location --image $image --os-type Linux --cpu 2 --memory 4 `
        --assign-identity --restart-policy Never --command-line 'tail -f /dev/null' `
        --environment-variables "COSMOS_ENDPOINT=$endpoint" "SOURCE_BASE64=$sourceBase64"
    ```

1. Confirm that the container is `Running` and capture its managed identity's principal object ID. Continue only when the ID is nonempty.

    ```powershell
    az container show --resource-group $resourceGroup --name $containerGroupName `
        --query 'containers[0].instanceView.currentState.state' --output tsv
    $principalId = az container show --resource-group $resourceGroup --name $containerGroupName `
        --query identity.principalId --output tsv
    $principalId
    ```

1. Grant temporary native Data Contributor. Retain the assignment ID for exact deletion later. Verify the returned principal, role ending in `0002`, and product-container scope.

    ```powershell
    $scope = '/dbs/cosmicworks/colls/product'
    $seedAssignment = [Guid]::NewGuid().ToString()
    az cosmosdb sql role assignment create --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $seedAssignment `
        --principal-id $principalId --scope $scope `
        --role-definition-id '00000000-0000-0000-0000-000000000002'
    ```

### Initialize the container workspace

1. Enter **container Bash** from **local PowerShell**. ACI exec starts one shell command; enter subsequent commands at the Bash prompt.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $containerGroupName --exec-command /bin/bash
    ```

1. Initialize the project in **container Bash**. Decode the source and install the required packages.

    ```bash
    dotnet new console -o /work/security
    cd /work/security
    printenv SOURCE_BASE64 | base64 --decode > Program.cs
    dotnet add package Microsoft.Azure.Cosmos
    dotnet add package Azure.Identity
    dotnet add package Newtonsoft.Json
    ```

1. Load the products in **container Bash**. Expect `Seed succeeded: 295 items.` and exit code `0`. Role assignments can take several minutes to propagate; wait and retry if needed.

    ```bash
    dotnet run -- seed
    echo $?
    ```

1. Return to **local PowerShell**. Exiting Bash leaves the idle container running and preserves your PowerShell variables.

    ```bash
    exit
    ```

Keep the container running between tasks so its workspace and cached catalog remain available.

## Task 3: Enforce and test read-only access

Role permissions are additive. Remove the temporary Contributor assignment before testing Data Reader, and keep the identity and network settings unchanged.

1. Add native Data Reader in **local PowerShell**, at the same scope. Data Reader is the application's intended steady-state permission.

    ```powershell
    $readerAssignment = [Guid]::NewGuid().ToString()
    az cosmosdb sql role assignment create --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $readerAssignment `
        --principal-id $principalId --scope $scope `
        --role-definition-id '00000000-0000-0000-0000-000000000001'
    ```

1. Delete the exact temporary seed assignment in **local PowerShell**.

    ```azurecli
    az cosmosdb sql role assignment delete --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $seedAssignment --yes
    ```

1. Inspect all native assignments for the principal in **local PowerShell**. Confirm that only Data Reader, ending in `0001`, remains at product-container scope.

    ```azurecli
    az cosmosdb sql role assignment list --resource-group $resourceGroup --account-name $account `
        --query "[?principalId=='$principalId'].{Role:roleDefinitionId,Scope:scope,Assignment:id}" --output table
    ```

1. Reenter **container Bash** from **local PowerShell**.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $containerGroupName --exec-command /bin/bash
    ```

1. Run the check in **container Bash**.

    ```bash
    cd /work/security
    dotnet run --no-build -- check
    echo $?
    ```

    Expect a successful read followed by a denied replacement, with exit code `0`. Allow time for role changes to propagate and rerun if needed before continuing.

    ```output
    Read succeeded.
    Write denied (403). Expected.
    0
    ```

1. Return to **local PowerShell** before changing account settings.

    ```bash
    exit
    ```

## Task 4: Block and restore the public network path

Disable and restore public network access while keeping the managed identity and Data Reader assignment unchanged.

> &#9888; This account has no private endpoint. Disabling public network access blocks all data access until you enable it again. Use only the lab account.

### Verify the blocked read

1. Disable public access in **local PowerShell**. Don't change any permissions or reload data.

    ```azurecli
    az cosmosdb update --resource-group $resourceGroup --name $account --public-network-access DISABLED
    ```

    > **Note:** This command can take **5 minutes or more** to complete and might not display progress while Azure applies the change. Wait for the PowerShell prompt to return before continuing.

1. Inspect the setting in **local PowerShell**. Expect `Disabled`.

    ```azurecli
    az cosmosdb show --resource-group $resourceGroup --name $account --query publicNetworkAccess --output tsv
    ```

1. Enter **container Bash** from **local PowerShell**.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $containerGroupName --exec-command /bin/bash
    ```

1. Run the point read in **container Bash**. Expect `Read denied (403).` and exit code `3`. Network changes can take up to 15 minutes to propagate; wait and repeat the read if needed.

    ```bash
    cd /work/security
    dotnet run --no-build -- read
    echo $?
    ```

1. Return to **local PowerShell** to restore public access, even if the test failed.

    ```bash
    exit
    ```

### Verify restored access and retained restrictions

1. Restore public access in **local PowerShell**. The final command needs to show `Enabled`. Keep Reader and key-based authentication settings unchanged.

    ```azurecli
    az cosmosdb update --resource-group $resourceGroup --name $account --public-network-access ENABLED
    az cosmosdb show --resource-group $resourceGroup --name $account --query publicNetworkAccess --output tsv
    ```

    > **Note:** The update command can take **5 minutes or more** to complete and might not display progress while Azure applies the change. Wait for the PowerShell prompt to return before continuing.

1. Reenter **container Bash** from **local PowerShell** for the final comparison.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $containerGroupName --exec-command /bin/bash
    ```

1. Repeat the read and authorization check in **container Bash**. Expect read success, then the read-success and write-denial pair, each with exit code `0`. Allow time for the network change to propagate and retry if needed.

    ```bash
    cd /work/security
    dotnet run --no-build -- read
    echo $?
    dotnet run --no-build -- check
    echo $?
    ```

1. Return to **local PowerShell** for cleanup.

    ```bash
    exit
    ```

Compare your results with the expected outcomes below. Record each result, timestamp, managed identity principal ID, and role scope without credentials or product values.

| Stage | Public access | Native role | Expected read | Expected replacement |
| --- | --- | --- | --- | --- |
| Before blocking | Enabled | Data Reader | Succeeds | Denied, 403 |
| Blocked | Disabled | Same Data Reader | Denied, 403 | Not attempted |
| Restored | Enabled | Same Data Reader | Succeeds | Denied, 403 |

Learn more about [managed identities in ACI](/azure/container-instances/container-instances-managed-identity), [Cosmos DB data-plane roles](/azure/cosmos-db/reference-data-plane-security), and [account network restrictions](/azure/cosmos-db/how-to-configure-firewall).

## Clean up resources

Remove this exercise's disposable resources when you finish, even after a partial or failed run. Run the group-deletion steps only if you created the group and it contains only this exercise's resources. If your lab provided `ResourceGroup1`, keep the group and use the individual account and container-group deletion commands instead.

1. Inspect the subscription, group, and resources in **local PowerShell**. Resolve any unexpected resource before deletion.

    ```azurecli
    az account show --query '{Subscription:name,Id:id}' --output table
    az group show --name $resourceGroup --query '{Name:name,Id:id}' --output json
    az resource list --resource-group $resourceGroup --query '[].{Name:name,Type:type}' --output table
    ```

1. Delete the inspected group in **local PowerShell**. Deleting the group permanently removes the account, its data, and the ACI host. Review the interactive confirmation before approving.

    ```azurecli
    az group delete --name $resourceGroup
    ```

1. Verify deletion in **local PowerShell**. Confirm that the result is `false`.

    ```azurecli
    az group exists --name $resourceGroup
    ```

If your lab provided the resource group, or the group holds other resources, delete only this exercise's account and container group:

```azurecli
az cosmosdb delete --name $account --resource-group $resourceGroup --yes
az container delete --name $containerGroupName --resource-group $resourceGroup --yes
```
