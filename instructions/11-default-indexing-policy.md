---
lab:
    title: 'Review the default index policy for an Azure Cosmos DB SQL API container with the portal'
    module: 'Module 6 - Define and implement an indexing strategy for Azure Cosmos DB SQL API'
---

# Review the default index policy for an Azure Cosmos DB SQL API container with the portal

Every container in Azure Cosmos DB has an indexing policy that directs the service on how to index items within the container. By default, this indexing policy indexes every property of every item. The default indexing policy makes it easy to get started with Azure Cosmos DB quickly as you don't have to think about indexing, performance, and management at the start of a project.

In this lab, you'll observe and manipulate the default index policy for a few containers using the Data Explorer.

## Create an Azure Cosmos DB SQL API account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you will select which of the APIs you want the account to support (for example, **Mongo API** or **SQL API**). Once the Azure Cosmos DB SQL API account is done provisioning, you can retrieve the endpoint and key and use them to connect to the Azure Cosmos DB SQL API account using the Azure SDK for .NET or any other SDK of your choice.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB SQL API** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Close your web browser window or tab.

## Seed the Azure Cosmos DB SQL API account with data

The [cosmicworks][nuget.org/packages/cosmicworks] command-line tool deploys sample data to any Azure Cosmos DB SQL API account. The tool is open-source and available through NuGet. You will install this tool to the Azure Cloud Shell and then use it to seed your database.

1. Start **Visual Studio Code**.

1. In **Visual Studio Code**, open the **Terminal** menu and then select **New Terminal** to open a new terminal instance.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

1. Install the [cosmicworks][nuget.org/packages/cosmicworks] command-line tool for global use on your machine.

    ```
    dotnet tool install --global cosmicworks
    ```
  
    > &#128161; This command may take a couple of minutes to complete. This command will output the warning message (*Tool 'cosmicworks' is already installed') if you have already installed the latest version of this tool in the past.

1. Run cosmicworks to seed your Azure Cosmos DB account with the following command-line options:

    | **Option** | **Value** |
    | ---: | :--- |
    | **--endpoint** | *The endpoint value you copied earlier in this lab* |
    | **--key** | *The key value you coped earlier in this lab* |
    | **--datasets** | *product* |

    ```
    cosmicworks --endpoint <cosmos-endpoint> --key <cosmos-key> --datasets product
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/** and your key is: **fDR2ci9QgkdkvERTQ==**, then the command would be:
    > ``cosmicworks --endpoint https://dp420.documents.azure.com:443/ --key fDR2ci9QgkdkvERTQ== --datasets product``

1. Wait for the **cosmicworks** command to finish populating the account with a database, container, and items.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

## View and manipulate the default indexing policy

When a container is created by code, portal, or a tool; the indexing policy is set to an intelligent default if you do not specify it otherwise. You will observe that default indexing policy and make a change to the policy.

1. In a web browser, navigate to the Azure portal (``portal.azure.com``).

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **name** is equivalent to **HL Headset**:

    ```
    SELECT * FROM p WHERE p.name = 'HL Headset'
    ```

1. Select **Execute Query**.

1. Observe the results of the query.

1. In the **Query** tab, select **Query Stats**.

1. Still in the **Query** tab, observe the value of the **Request Charge** field within the **Query Statistics** section.

    > &#128221; All paths are currently indexed, so this query should be relatively efficient.

1. Within the **products** container node of the **SQL API** navigation tree, select **Scale & Settings**.

1. Observe the default indexing policy within the **Indexing Policy** section:

    ```
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        {
          "path": "/*"
        }
      ],
      "excludedPaths": [
        {
          "path": "/\"_etag\"/?"
        }
      ]
    }
    ```

    > &#128221; This default policy will index all possible paths with the exception of **_etag**.

1. Within the editor, replace the content of the indexing policy to only index the **/price** path:

    ```
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        {
          "path": "/price/?"
        }
      ],
      "excludedPaths": [
        {
          "path": "/*"
        }
      ]
    }
    ```

1. Select **Save** to persist your changes.

1. Select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **name** is equivalent to **HL Headset**:

    ```
    SELECT * FROM p WHERE p.name = 'HL Headset'
    ```

1. Select **Execute Query**.

1. Observe the results of the query.

1. In the **Query** tab, select **Query Stats**.

1. Still in the **Query** tab, observe the value of the **Request Charge** field within the **Query Statistics** section.

    > &#128221; Now that the **name** property is not indexed, the request charge has increased.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **price** is greater than **$3,000**:

    ```
    SELECT * FROM p WHERE p.price > 3000
    ```

1. Select **Execute Query**.

1. Observe the results of the query.

1. In the **Query** tab, select **Query Stats**.

1. Still in the **Query** tab, observe the value of the **Request Charge** field within the **Query Statistics** section.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[nuget.org/packages/cosmicworks]: https://www.nuget.org/packages/cosmicworks/
