---
lab:
  title: 'Create your Azure Cosmos DB account'
  module: 'Setup'
---

# Create your Azure Cosmos DB account

Every exercise in this course runs against one Azure Cosmos DB for NoSQL account. Create it once here, and reuse it throughout.

The shared setup script provisions the account, the databases and containers your exercise needs, and the data-plane role assignment that lets you read and write items. It's safe to run more than once: existing resources are left alone.

## Before you start

You need:

- An Azure subscription with permission to create resources and assign roles.
- The tools from [Set up your lab environment](00-setup-local-environment.md), including PowerShell 7 and the Azure CLI.
- An active `az login` session.

## Choose a region

Container copy jobs run in the account's write region and aren't available everywhere. If you plan to complete the change feed exercise, pick a region from the [supported list](https://learn.microsoft.com/azure/cosmos-db/container-copy#supported-regions). `eastus`, `westus2`, `northeurope`, and `uksouth` all work.

The setup script warns you if the region you choose can't run copy jobs.

## Run the setup script

1. In **Visual Studio Code**, open the cloned lab repository.

1. In the **Explorer** pane, browse to **Allfiles/Labs/Shared**.

1. Open the context menu for the folder and select **Open in Integrated Terminal**.

1. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Set variables for the resource group and region you want to use.

    ```powershell
    $resourceGroup = "dp420"
    $location = "eastus"
    ```

    > [!NOTE]
    > If a resource group already exists for this course, set `$resourceGroup` to that name. Some lab environments provide a resource group and prevent you from creating others. The script uses an existing group as it finds it, and creates one only when the name you give doesn't exist yet.

    A resource group's own location is metadata only, so the Azure Cosmos DB account is created in `$location` whether or not that matches the group.

1. Run the script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one by adding six random characters to a prefix, giving a name like `dp420laba7f3k9`. Pass `-NamePrefix` to change the prefix, or `-AccountName` to target an account that already exists.

    Account creation takes 5-10 minutes, and loading the sample data takes a few minutes more.

1. When the script finishes, record the **Account name** and **Account endpoint** values it prints. The endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

    Every exercise asks for this endpoint. Keep it somewhere you can find it.

## What the script creates

| Resource | Configuration |
| :--- | :--- |
| Resource group | The name you passed, in the region you passed |
| Azure Cosmos DB account | API for NoSQL, provisioned throughput, session consistency, **key-based authentication disabled** |
| Role assignment | Cosmos DB Built-in Data Contributor, scoped to the account, for your signed-in identity |
| Databases and containers | Determined by the lab profile. See [Prepare the lab data](00-prepare-lab-data.md) |

## Why there are no keys

The script creates the account with `--disable-local-auth true`, so the account accepts Microsoft Entra ID authentication only. Account keys don't work and aren't available to copy.

That's why the role assignment matters. Your Azure role grants control-plane permissions, which cover creating databases and containers, but grant nothing over the data inside them. Azure Cosmos DB controls data access with its own separate set of roles, and the script assigns you one.

> **Note**: A new role assignment takes a few minutes to propagate. If an exercise fails with a 403 error shortly after setup, wait a moment and run it again.

## Clean up

When you finish the course, delete the resource group to stop all charges:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, delete only the Azure Cosmos DB account instead:

```azurecli
az cosmosdb delete --name <your-account-name> --resource-group $resourceGroup --yes
```

## Next step

Continue to [Prepare the lab data](00-prepare-lab-data.md).
