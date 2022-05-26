---
lab:
    title: 'Create an Azure Cosmos DB SQL API container using Azure Resource Manager templates'
    module: 'Module 12 - Manage an Azure Cosmos DB SQL API solution using DevOps practices'
---

# Create an Azure Cosmos DB SQL API container using Azure Resource Manager templates

Azure Resource Manager templates are JSON files that declaratively define the infrastructure that you wish to deploy to Azure. Azure Resource Manager templates are a common infrastrucutre-as-code solution to deploying services to Azure. Bicep, takes the concept a bit further by defining an easier to read domain-specific language that can be used to create JSON templates.

In this lab, you'll create a new Azure Cosmos DB account, database, and container using an Azure Resource Manager template. You will first create the template from raw JSON, then you will create the template using the Bicep domain-specific language.

## Prepare your development environment

If you have not already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/microsoftlearning/dp-420-cosmos-db-dev`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, open the local folder you selected in **Visual Studio Code**.

## Create Azure Cosmos DB SQL API resources using Azure Resource Manager templates

The **Microsoft.DocumentDB** resource provider in Azure Resource Manager makes it possible to deploy accounts, databases, and containers using JSON files. While the files may be complex, they do follow a predictable format and can be written with the assistance of a Visual Studio Code extension.

> &#128161; If you are stuck and cannot figure out a syntax error with your template, use this [solution Azure Resource Manager template][github.com/arm-template-guide] as a guide.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **31-create-container-arm-template** folder.

1. Open the **deploy.json** file.

1. Observe the empty Azure Resource Manager template:

    ```
    {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "resources": [
        ]
    }
    ```

1. Within the **resources** array, add a new JSON object to create a new Azure Cosmos DB account:

    ```
    {
        "type": "Microsoft.DocumentDB/databaseAccounts",
        "apiVersion": "2021-05-15",
        "name": "[concat('csmsarm', uniqueString(resourceGroup().id))]",
        "location": "[resourceGroup().location]",
        "properties": {
            "databaseAccountOfferType": "Standard",
            "locations": [
                {
                    "locationName": "westus"
                }
            ]
        }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Resource type** | *Microsoft.DocumentDB/databaseAccounts* |
    | **API version** | *2021-05-15* |
    | **Account name** | *csmsarm* &amp; *unique string generated from account name*  |
    | **Location** | *Resource group's current location* |
    | **Account offer type** | *Standard* |
    | **Locations** | *Only West US* |

1. Save the **deploy.json** file.

1. Open the context menu for the **31-create-container-arm-template** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **31-create-container-arm-template** folder.

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

1. Create a new variable name **resourceGroup** using the name of the resource group you created or viewed earlier in this lab using the following command:

    ```
    $resourceGroup="<resource-group-name>"
    ```

    > &#128221; For example, if your resource group is named **dp420**, the command will be **$resourceGroup="dp420"**.

1. Use the **echo** cmdlet to write the value of the **$resourceGroup** variable to the terminal output using the following command:

    ```
    echo $resourceGroup
    ```

1. Deploy the Azure Resource Manager template using the [az deployment group create][docs.microsoft.com/cli/azure/deployment/group] command:

    ```
    az deployment group create --name "arm-deploy-account" --resource-group $resourceGroup --template-file .\deploy.json
    ```

1. Leave the integrated terminal open and return to the editor for the **deploy.json** file.

1. Within the **resources** array, add another new JSON object to create a new Azure Cosmos DB SQL API database:

    ```
    ,
    {
        "type": "Microsoft.DocumentDB/databaseAccounts/sqlDatabases",
        "apiVersion": "2021-05-15",
        "name": "[concat('csmsarm', uniqueString(resourceGroup().id), '/cosmicworks')]",
        "dependsOn": [
            "[resourceId('Microsoft.DocumentDB/databaseAccounts', concat('csmsarm', uniqueString(resourceGroup().id)))]"
        ],
        "properties": {
            "resource": {
                "id": "cosmicworks"
            }
        }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Resource type** | *Microsoft.DocumentDB/databaseAccounts/sqlDatabases* |
    | **API version** | *2021-05-15* |
    | **Account name** | *csmsarm* &amp; *unique string generated from account name* &amp; */cosmicworks*  |
    | **Resource id** | *cosmicworks* |
    | **Dependencies** | *databaseAccount created earlier in the template* |

1. Save the **deploy.json** file.

1. Return to the integrated terminal.

1. Deploy the Azure Resource Manager template using the **az deployment group create** command:

    ```
    az deployment group create --name "arm-deploy-database" --resource-group $resourceGroup --template-file .\deploy.json
    ```

1. Leave the integrated terminal open and return to the editor for the **deploy.json** file.

1. Within the **resources** array, add another new JSON object to create a new Azure Cosmos DB SQL API container:

    ```
    ,
    {
        "type": "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers",
        "apiVersion": "2021-05-15",
        "name": "[concat('csmsarm', uniqueString(resourceGroup().id), '/cosmicworks/products')]",
        "dependsOn": [
            "[resourceId('Microsoft.DocumentDB/databaseAccounts', concat('csmsarm', uniqueString(resourceGroup().id)))]",
            "[resourceId('Microsoft.DocumentDB/databaseAccounts/sqlDatabases', concat('csmsarm', uniqueString(resourceGroup().id)), 'cosmicworks')]"
        ],
        "properties": {
            "options": {
                "throughput": 400
            },
            "resource": {
                "id": "products",
                "partitionKey": {
                    "paths": [
                        "/categoryId"
                    ]
                }
            }
        }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Resource type** | *Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers* |
    | **API version** | *2021-05-15* |
    | **Account name** | *csmsarm* &amp; *unique string generated from account name* &amp; */cosmicworks/products*  |
    | **Resource id** | *products* |
    | **Throughput** | *400* |
    | **Partition key** | */categoryId* |
    | **Dependencies** | *Account and database created earlier in the template* |

1. Save the **deploy.json** file.

1. Return to the integrated terminal.

1. Deploy the final Azure Resource Manager template using the **az deployment group create** command:

    ```
    az deployment group create --name "arm-deploy-container" --resource-group $resourceGroup --template-file .\deploy.json
    ```

1. Close the integrated terminal.

## Observe deployed Azure Cosmos DB resources

Once your Azure Cosmos DB SQL API resources are deployed, you can navigate to the resources in the Azure portal. Using the Data Explorer, you will validate that the account, database, and container were all deployed and configured correctly.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab with the **csmsarm** prefix.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **Scale & Settings**.

1. Observe the values within the **Scale** section. Specifically, observe that the **Manual** option is selected in the **Throughput** section and that the provisioned throughput is set to **400** RU/s.

1. Observe the values within the **Settings** section. Specifically, observe that the **Partition key** value is set to **/categoryId**.

1. Close your web browser window or tab.

## Create Azure Cosmos DB SQL API resources using Bicep templates

Bicep is an efficient domain-specific language that makes it simpler and easier to deploy Azure resources than Azure Resource Manager templates. You will deploy the same exact resource using Bicep and a different name to illustrate the difference\[s\].

> &#128161; If you are stuck and cannot figure out a syntax error with your template, use this [solution Bicep template][github.com/bicep-template-guide] as a guide.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **31-create-container-arm-template** folder.

1. Open the empty **deploy.bicep** file.

1. Within the file, add a new object to create a new Azure Cosmos DB account:

    ```
    resource Account 'Microsoft.DocumentDB/databaseAccounts@2021-05-15' = {
      name: 'csmsbicep${uniqueString(resourceGroup().id)}'
      location: resourceGroup().location
      properties: {
        databaseAccountOfferType: 'Standard'
        locations: [
          { 
            locationName: 'westus' 
          }
        ]
      }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Alias** | *Account* |
    | **Name** | *csmsarm* &amp; *unique string generated from account name* |
    | **Resource type** | *Microsoft.DocumentDB/databaseAccounts/sqlDatabases* |
    | **API version** | *2021-05-15* |
    | **Location** | *Resource group's current location* |
    | **Account offer type** | *Standard* |
    | **Locations** | *Only West US* |

1. Save the **deploy.bicep** file.

1. Open the context menu for the **31-create-container-arm-template** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Create a new variable name **resourceGroup** using the name of the resource group you created or viewed earlier in this lab using the following command:

    ```
    $resourceGroup="<resource-group-name>"
    ```

    > &#128221; For example, if your resource group is named **dp420**, the command will be **$resourceGroup="dp420"**.

1. Deploy the Bicep template using the **az deployment group create** command:

    ```
    az deployment group create --name "bicep-deploy-account" --resource-group $resourceGroup --template-file .\deploy.bicep
    ```

1. Leave the integrated terminal open and return to the editor for the **deploy.bicep** file.

1. Within the file, add another new object to create a new Azure Cosmos DB database:

    ```
    resource Database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-05-15' = {
      parent: Account
      name: 'cosmicworks'
      properties: {
        resource: {
            id: 'cosmicworks'
        }
      }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Parent** | *Account created earlier in the template* |
    | **Alias** | *Database* |
    | **Name** | *cosmicworks*  |
    | **Resource type** | *Microsoft.DocumentDB/databaseAccounts/sqlDatabases* |
    | **API version** | *2021-05-15* |
    | **Resource id** | *cosmicworks* |

1. Save the **deploy.bicep** file.

1. Return to the integrated terminal.

1. Deploy the Bicep template using the **az deployment group create** command:

    ```
    az deployment group create --name "bicep-deploy-database" --resource-group $resourceGroup --template-file .\deploy.bicep
    ```

1. Leave the integrated terminal open and return to the editor for the **deploy.bicep** file.

1. Within the file, add another new object to create a new Azure Cosmos DB container:

    ```
    resource Container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-05-15' = {
      parent: Database
      name: 'products'
      properties: {
        options: {
          throughput: 400
        }
        resource: {
          id: 'products'
          partitionKey: {
            paths: [
              '/categoryId'
            ]
          }
        }
      }
    }
    ```

    The object is configured with the following settings:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Parent** | *Database created earlier in the template* |
    | **Alias** | *Container* |
    | **Name** | *products*  |
    | **Resource id** | *products* |
    | **Throughput** | *400* |
    | **Partition key path** | */categoryId* |

1. Save the **deploy.bicep** file.

1. Return to the integrated terminal.

1. Deploy the final Bicep template using the **az deployment group create** command:

    ```
    az deployment group create --name "bicep-deploy-container" --resource-group $resourceGroup --template-file .\deploy.bicep
    ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

## Observe Bicep template deployment results

Bicep deployments can be validated using many of the same techniques as Azure Resource Manager deployments. Not only will you validate that your account, database, and container were successfully deployed; you will also view the deployment history across all six deployments.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab.

1. Within the resource group, navigate to the **Deployments** pane.

1. Observe the six deployments from the Azure Resource Manager templates and Bicep files.

1. Still within the resource group, navigate to the **Overview** pane.

1. Still within the resource group, select the **Azure Cosmos DB account** resource you created in this lab with the **csmsbicep** prefix.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **Scale & Settings**.

1. Observe the values within the **Scale** section. Specifically, observe that the **Manual** option is selected in the **Throughput** section and that the provisioned throughput is set to **400** RU/s.

1. Observe the values within the **Settings** section. Specifically, observe that the **Partition key** value is set to **/categoryId**.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/cli/azure/deployment/group]: https://docs.microsoft.com/cli/azure/deployment/group
[github.com/arm-template-guide]: https://raw.githubusercontent.com/Sidney-Andrews/acdbsad/solutions/31-create-container-arm-template/deploy.json
[github.com/bicep-template-guide]: https://raw.githubusercontent.com/Sidney-Andrews/acdbsad/solutions/31-create-container-arm-template/deploy.bicep
