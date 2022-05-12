---
lab:
    title: 'Adjust provisioned throughput using an Azure CLI script'
    module: 'Module 12 - Manage an Azure Cosmos DB SQL API solution using DevOps practices'
---

# Adjust provisioned throughput using an Azure CLI script

The Azure CLI is a set of commands that you can use to manage various resources across Azure. Azure Cosmos DB has a rich command group that can be used to manage various facets of an Azure Cosmos DB account regardless of the selected API.

In this lab, you'll create an Azure Cosmos DB account, database, and container using the Azure CLI. You will then make adjustments to the provisioned throughput using the Azure CLI.

## Log in to the Azure CLI

Before using the Azure CLI, you must first check the version of the CLI and login using your Azure credentials.

1. Start **Visual Studio Code**.

1. Open the **Terminal** menu and then select **New Terminal** to open a new terminal instance.

1. View the version of the Azure CLI using the following command:

    ```
    az --version
    ```

1. View the most common Azure CLI command groups using the following command:

    ```
    az --help
    ```

1. Begin the interactive login procedure for the Azure CLI using the following command:

    ```
    az login
    ```

1. The Azure CLI will automatically open a web browser window or tab. within the browser instance, sign into the Azure CLI using the Microsoft credentials associated with your subscription.

1. Close your web browser window or tab.

1. Check if your lab provider has created a resource group for you, if so, record its name since you will need it in the next section.

    ```
    az group list --query "[].{ResourceGroupName:name}" -o table
    ```
    
    This command could return multiple Resource Group names.

1. (Optional) ***If no Resource Group was created for you***, choose a Resource Group name and create it. *Be aware that some lab envrionments might be locked down and you will need an administrator to create the Resource Group for you.*

    i. Get the your location name closet to you from this list

    ```
    az account list-locations --query "sort_by([].{YOURLOCATION:name, DisplayName:regionalDisplayName}, &YOURLOCATION)" --output table
    ```

    ii. Create the resource group.  *Be aware that some lab envrionments might be locked down and you will need an administrator to create the Resource Group for you.*
    ```
    az group create --name YOURRESOURCEGROUPNAME --location YOURLOCATION
    ```

## Create Azure Cosmos DB account using the Azure CLI

The **cosmosdb** command group contains basic commands to create and manage Azure Cosmos DB accounts using the CLI. Since an Azure Cosmos DB account has an addressable URI, it's important to create a globally unique name for your new account, even if you create it via script.

1. Return to the terminal instance already open within **Visual Studio Code**.

1. View the most command Azure CLI commands related to **Azure Cosmos DB** using the following command:

    ```
    az cosmosdb --help
    ```

1. Create a new variable named **suffix** with the [Get-Random][docs.microsoft.com/powershell/module/microsoft.powershell.utility/get-random] PowerShell cmdlet using the following command:

    ```
    $suffix=Get-Random -Maximum 1000000
    ```

    > &#128221; The Get-Random cmdlet generates a random integer between 0 and 1,000,000. This is useful because our services requires a globally unique name.

1. Create another new variable name **accountName** using the hard-coded string **csms** and variable substitution to inject the value of the **$suffix** variable using the following command:

    ```
    $accountName="csms$suffix"
    ```

1. Create another new variable name **resourceGroup** using the name of the resource group you created or viewed earlier in this lab using the following command:

    ```
    $resourceGroup="<resource-group-name>"
    ```

    > &#128221; For example, if your resource group is named **dp420**, the command will be **$resourceGroup="dp420"**.

1. Use the **echo** cmdlet to write the value of the **$accountName** and **$resourceGroup** variables to the terminal output using the following command:

    ```
    echo $accountName
    echo $resourceGroup
    ```

1. View the options for **az cosmosdb create** using the following command:

    ```
    az cosmosdb create --help
    ```

1. Create a new Azure Cosmos DB account using the predefined variables and the following command:

    ```
    az cosmosdb create --name $accountName --resource-group $resourceGroup
    ```

1. Wait for the **create** command to finish execution and return before proceeding forward with this lab.

    > &#128161; The **create** command can take anywhere from two to twelve minutes to complete, on average.

## Create Azure Cosmos DB SQL API resources using the Azure CLI

The **cosmosdb sql** command group contains commands for managing SQL API-specific resources for Azure Cosmos DB. You can always use the **--help** flag to review the options for these command groups.

1. Return to the terminal instance already open within **Visual Studio Code**.

1. View the most command Azure CLI command groups related to **Azure Cosmos DB SQL API** using the following command:

    ```
    az cosmosdb sql --help
    ```

1. View the Azure CLI commands for managing **Azure Cosmos DB SQL API** databases using the following command:

    ```
    az cosmosdb sql database --help
    ```

1. Create a new Azure Cosmos DB database using the predefined variables, the database name **cosmicworks**, and the following command:

    ```
    az cosmosdb sql database create --name "cosmicworks" --account-name $accountName --resource-group $resourceGroup
    ```

1. Wait for the **create** command to finish execution and return before proceeding forward with this lab.

1. View the Azure CLI commands for managing **Azure Cosmos DB SQL API** containers using the following command:

    ```
    az cosmosdb sql container --help
    ```

1. Create a new Azure Cosmos DB container using the predefined variables, the database name **cosmicworks**, the container name **products**,  and the following command:

    ```
    az cosmosdb sql container create --name "products" --throughput 400 --partition-key-path "/categoryId" --database-name "cosmicworks" --account-name $accountName --resource-group $resourceGroup
    ```

1. Wait for the **create** command to finish execution and return before proceeding forward with this lab.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab with the **csms** prefix.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **Scale & Settings**.

1. Observe the values within the **Scale** tab. Specifically, observe that the **Manual** option is selected in the **Throughput** section and that the provisioned throughput is set to **400** RU/s.

1. Close your web browser window or tab.

## Adjust the throughput of an existing container using the Azure CLI

The Azure CLI can be used to migrate a container between manual and autoscale provisioning of throughput. If the container is using autoscale throughput, the CLI can be used to dynamically adjust the maximum allowed throughput value.

1. Return to the terminal instance already open within **Visual Studio Code**.

1. View the Azure CLI commands for managing **Azure Cosmos DB SQL API** container throughput using the following command:

    ```
    az cosmosdb sql container throughput --help
    ```

1. Migrate the **products** container throughput from manual provisioning to autoscale using the following command:

    ```
    az cosmosdb sql container throughput migrate --name "products" --throughput-type autoscale --database-name "cosmicworks" --account-name $accountName --resource-group $resourceGroup
    ```

1. Wait for the **migrate** command to finish execution and return before proceeding forward with this lab.

1. Query the the **products** container to determine the minimum possible throughput value using the following command:

    ```
    az cosmosdb sql container throughput show --name "products" --query "resource.minimumThroughput" --output "tsv" --database-name "cosmicworks" --account-name $accountName --resource-group $resourceGroup
    ```

1. Update the maximum autoscale throughput of the **products** container from the default value of **4,000** to a new value of **5,000** using the following command:

    ```
    az cosmosdb sql container throughput update --name "products" --max-throughput 5000 --database-name "cosmicworks" --account-name $accountName --resource-group $resourceGroup
    ```

1. Wait for the **update** command to finish execution and return before proceeding forward with this lab.

1. Close **Visual Studio Code**.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab with the **csms** prefix.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **Scale & Settings**.

1. Observe the values within the **Scale** tab. Specifically, observe that the **Autoscale** option is selected in the **Throughput** section and that the provisioned throughput is set to **5,000** RU/s.

1. Close your web browser window or tab.

[docs.microsoft.com/powershell/module/microsoft.powershell.utility/get-random]: https://docs.microsoft.com/powershell/module/microsoft.powershell.utility/get-random
