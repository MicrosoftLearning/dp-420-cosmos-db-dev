---
lab:
  title: 'Create your Azure Cosmos DB account'
  module: 'Setup'
---

# Create your Azure Cosmos DB account

Use this guide when your exercise calls for the shared `core` account. If your exercise specifies a different profile or a disposable account, follow its setup steps instead.

The shared setup script provisions the account, the databases and containers your exercise needs, and the data-plane role assignment that lets you read and write items. Existing containers keep their settings, but rerunning setup reloads matching sample items. Verify an existing account before deciding whether it needs setup again.

## Before you start

You need:

- An Azure subscription with permission to create resources and assign roles.
- The tools from [Set up your lab environment](00-setup-local-environment.md), including PowerShell 7 and the Azure CLI.
- An active `az login` session.

## Choose a region

Container copy jobs run in the account's write region and aren't available everywhere. If you plan to complete the change feed exercise, pick a region from the [supported list](https://learn.microsoft.com/azure/cosmos-db/container-copy#supported-regions). `eastus`, `westus2`, `northeurope`, and `uksouth` all work.

Before creating resources, setup checks the reported Cosmos DB regional status and your subscription's regional access. The shared `core` account also needs a supported container-copy region for the change feed exercise. Setup stops if a check fails. Other profiles check their own regional requirements; see [Check regional availability](README.md#check-regional-availability).

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

1. Run the script for the `core` profile.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -LabProfile core
    ```

    To check the region without creating Azure resources, add `-PreflightOnly` to this command. Remove that switch when you're ready to run setup. The check doesn't reserve capacity or replace the exercise's other prerequisites.

    Azure Cosmos DB account names have to be globally unique, so the script builds one by adding six random characters to a prefix, giving a name like `dp420laba7f3k9`. Pass `-NamePrefix` to change the prefix, or `-AccountName` to target an account that already exists.

    Account creation takes 5-10 minutes, and loading the sample data takes a few minutes more.

1. When the script finishes, record the **Account name** and **Account endpoint** values it prints. The endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

    Keep these values for the exercises that reuse this account.

1. Set the account name from the script output and verify the setup. If you already have this account, run this check before rerunning setup.

    ```powershell
    $accountName = "<your-account-name>"
    ./verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile core
    ```

    Resolve any failed checks before continuing. If you need to rerun setup, pass `-AccountName $accountName` to target this same account.

## What the script creates

| Resource | Configuration |
| :--- | :--- |
| Resource group | Reuses the group you passed, or creates it in the selected region if it doesn't exist |
| Azure Cosmos DB account | API for NoSQL, provisioned throughput, session consistency, **key-based authentication disabled** |
| Role assignment | Cosmos DB Built-in Data Contributor, scoped to the account, for your signed-in identity |
| Databases and containers | Determined by the lab profile. See [Prepare the lab data](00-prepare-lab-data.md) |

## Why there are no keys

The script disables key-based authentication on the account. Use your Microsoft Entra ID identity; you don't need to find or copy account keys.

That's why the role assignment matters. Your Azure role grants control-plane permissions, which cover creating databases and containers, but grant nothing over the data inside them. Azure Cosmos DB controls data access with its own separate set of roles, and the script assigns you one.

> **Note**: A new role assignment takes a few minutes to propagate. If an exercise fails with a 403 error shortly after setup, wait a moment and run it again.

## Clean up

Keep the shared account until you finish the exercises that reuse it. Delete the resource group only if you created it for these exercises and it contains no resources you need to keep:

```azurecli
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, or the group contains other resources, keep it. Delete only the lab account you no longer need, using the account name you recorded:

```azurecli
az cosmosdb delete --name $accountName --resource-group $resourceGroup --yes
```

## Next step

Check the expected data in [Prepare the lab data](00-prepare-lab-data.md), then return to your exercise.
