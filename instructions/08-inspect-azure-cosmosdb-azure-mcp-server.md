---
lab:
  title: Inspect Azure Cosmos DB with Azure MCP Server
  module: Module 8 - Implement AI-Assisted Development Tools for Azure Cosmos DB
  description: Use Azure MCP Server in Visual Studio Code to inspect the CosmicWorks catalog, query items, and verify the tool calls and results.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
    - Azure MCP Server
---

# Inspect Azure Cosmos DB with Azure MCP Server

In this exercise, you connect an AI assistant to the CosmicWorks product catalog through a Model Context Protocol (MCP) server. You inspect and query the catalog with natural-language requests, then verify the tool calls and results.

## Before you start

> &#10071; You need a **GitHub account with access to GitHub Copilot** for the Copilot tasks in this exercise. If you don't have an account, [create a free GitHub account](https://github.com/signup) and verify your email address before starting. [GitHub Copilot Free](https://docs.github.com/en/copilot/get-started/plans) is available with usage limits.

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

This exercise also requires:

- [Node.js](https://nodejs.org) 22 or later, which supplies the `npx` command the MCP server runs under.
- Visual Studio Code with the [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension.

## Set up your Azure Cosmos DB resources

This exercise uses the `core` profile, which creates the CosmicWorks catalog and supporting containers. The MCP tasks inspect and query only the `cosmicworks/product` container.

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

1. Set variables for the resource group and region. If your lab environment provides a resource group, use that name. Otherwise, use a new group that contains only this exercise's resources.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab08 -LabProfile core
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab08a7f3k9`.

1. Wait for **Setup complete** in the terminal.

1. Record the **Account name** and **Account endpoint** values the script prints. The Cosmos DB endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set a variable for the account name so the Azure CLI commands in this exercise can use it.

    ```powershell
    $accountName = "<your-account-name>"
    ```

1. Run verification to check the resources.

    ```powershell
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile core
    ```

    Continue only after verification succeeds.

Setup creates these resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, key-based authentication disabled |
| `cosmicworks` database | Holds the catalog and the core profile's supporting containers |
| `cosmicworks/product` | `/categoryId`, autoscale maximum of 1,000 request units per second, 295 products |
| `cosmicworks/productMeta` | `/type`, autoscale maximum of 1,000 request units per second, 237 category and tag documents |
| `cosmicworks/leases` | `/id`, 400 request units per second, empty |
| `cosmicworks/operations` and `cosmicworks/bulkload` | `/categoryId`, each with an autoscale maximum of 1,000 request units per second, empty |
| Cosmos DB role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

## Task 1: Configure and start Azure MCP Server

1. In **Explorer**, under **Allfiles/Labs/Shared**, create a folder called **ai-tools-lab**. If the folder already exists, reuse it.

1. Select **File > Open Folder** and open **ai-tools-lab** as the workspace folder.

1. Under **ai-tools-lab**, create a folder called **.vscode**. Inside **.vscode**, create **mcp.json** and add this configuration:

    ```json
    {
      "servers": {
        "Azure MCP Server": {
          "command": "npx",
          "args": ["-y", "@azure/mcp@latest", "server", "start"]
        }
      }
    }
    ```

1. If the Chat pane isn't open, select **View > Chat** from the menu bar.

1. In Chat, select **Agent** from the mode selector.

1. If prompted, sign in to GitHub Copilot. In the model picker, select an available model or **Auto**.

1. Press **Ctrl+Shift+P**, enter **MCP: List Servers**, and select the command. Choose **Azure MCP Server**. If it isn't running, select **Start Server**. Review any server-trust prompt before continuing.

Continue only when the Azure MCP Server is running and its tools are available in Chat.

## Task 2: Inspect and query the catalog through MCP

Keep the same Chat conversation for these requests. Replace **<your-account-name>** with the account name recorded during setup. If the assistant asks for a subscription or resource group, provide the values you used for this exercise.

In Chat, enter the following request:

```text
Use the Azure MCP Server to count all items in the product container
in the cosmicworks database for account <your-account-name>.
Return the total count, not a sample of documents. Use this account
and database for my remaining requests.
```

Review the tool call and approve it if prompted. Confirm that it targets your lab account and returns a count of **295**.

Next, ask the assistant to inspect the document structure:

```text
Infer the schema of the product container in the cosmicworks database
for my Azure Cosmos DB account.
```

The schema tool samples documents and reports top-level properties, inferred types, and property occurrence counts. Compare the result with the catalog fields: `id`, `categoryId`, `categoryName`, `sku`, `name`, `description`, `price`, and `tags`. The sample is not a guarantee that every document has the same structure.

Ask for the most recently modified items:

```text
Show me the 5 most recently modified items in the product container.
```

Inspect the returned documents and their `_ts` values. The recent-items tool orders documents by this system timestamp in descending order. Documents can share a timestamp, so the exact items and their order can vary. Keep one returned item's `id` and `categoryId` for Task 3.

Then filter the catalog and request only the fields you need:

```text
Query the product container for items where categoryId is
3E4CEACD-D007-46EB-82D7-31F6141752B2, and return only name and price.
```

Review and approve each tool call when prompted. Confirm that the query filters on the specified category ID and returns only `name` and `price`.

## Task 3: Verify the results and the tool's scope

Verify a returned item and review the schema tool's limitations.

1. Expand a tool call from Task 2. Confirm that it comes from **Azure MCP Server** and targets your account, **cosmicworks**, and **product**.

1. Use the `id` and `categoryId` you recorded from the recent-items result. Replace both placeholders in this request:

    ```text
    Retrieve item <item-id> from the product container in the cosmicworks
    database for the same account, using the Azure MCP Server.
    Use partition key <category-id>. Show its id, categoryId, name, and price.
    ```

1. Inspect the tool's arguments and returned document. Confirm that the partition key matches the item's `categoryId` and that `name` and `price` agree with the earlier result. Supplying the partition key scopes the item lookup to that partition.

1. Explain the limits of the schema result. Which properties appear in the sample? Does a top-level `array` or `object` type describe all nested fields? The schema tool doesn't inspect nested structures recursively. To inspect any nested values it contains, use the retrieved document.

These catalog tools only read data. The setup script assigns **Cosmos DB Built-in Data Contributor**, which also permits writes. Review each tool's source and requested action before approving it.

Identify one decision the MCP tools don't make for you, such as choosing the partition key, setting throughput, or granting access. Describe what evidence you need before making that decision.

## Clean up resources

When you finish this exercise, delete its resources if you no longer need them. Delete the resource group only if you created it for this exercise and every resource in it can be removed:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, keep it. Delete only the Cosmos DB account you created for this exercise, after confirming that no other application uses it:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

Keep shared and lab-provided resource groups. Don't delete a reused Cosmos DB account that other exercises or applications use.

The provisioned-throughput containers in this exercise incur throughput and storage charges while they exist.
