---
lab:
    title: 'Optimize an Azure Cosmos DB SQL API container indexing policy for a query'
    module: 'Module 10 - Optimize query performance in Azure Cosmos DB SQL API'
---

# Optimize an Azure Cosmos DB SQL API container's indexing policy for a query

When planning for an Azure Cosmos DB SQL API account, knowing our most popular queries can help us tune the indexing policy so that queries are as performant as possible.

In this lab, we will use the Data Explorer to test SQL queries with the default indexing policy and an indexing policy that includes a composite index.

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
    | **Capacity mode** | *Serverless* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Data Explorer** pane.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Create new* &vert; *cosmicworks* |
    | **Container id** | *products* |
    | **Partition key** | */categoryId* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

1. In the resource blade, navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Close your web browser window or tab.

## Seed your Azure Cosmos DB SQL API account with sample data

You will use a command-line utility that creates a **cosmicworks** database and a **products** container. The tool will then create a set of items that you will observe using the change feed processor running in your terminal window.

1. In **Visual Studio Code**, open the **Terminal** menu and then select **Split Terminal** to open a new terminal side by side with your existing instance.

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

## Execute SQL queries and measure their request unit charge

Before you modify the indexing policy, first, you will run a few sample SQL queries to get a baseline request unit charge expressed in RUs.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Select **Execute Query** to run the default query:

    ```
    SELECT * FROM c
    ```

1. Observe the results of the query. Select **Query Stats** to view the request unit charge in RUs.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **name** is equivalent to **HL Headset**:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p    
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge is almost the same as the first query.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **name** is equivalent to **HL Headset**:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p
    ORDER BY
        p.categoryName DESC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge has increased due to the **ORDER BY** clause.

## Create a composite index in the indexing policy

Now, you will need to create a composite index if you sort your items using multiple properties. In this task, you will create a composite index to sort items by their categoryName, and then their actual name.

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **categoryName** in descending order first, and then by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p
    ORDER BY
        p.categoryName DESC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. The query should fail with the error **The order by query does not have a corresponding composite index that it can be served from**.

1. In the **Data Explorer**, expand the **cosmicworks** database node, expand the **products** container node, and then select **Settings**.

1. In the **Settings** tab, navigate to the **Indexing Policy** section.

1. Observe the default indexing policy:

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

1. Replace the indexing policy with this modified JSON object and then **Save** the changes:

    ```
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        {
          "path": "/*"
        }
      ],
      "excludedPaths": [],
      "compositeIndexes": [
        [
          {
            "path": "/categoryName",
            "order": "descending"
          },
          {
            "path": "/price",
            "order": "ascending"
          }
        ]
      ]
    }
    ```

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **categoryName** in descending order first, and then by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p
    ORDER BY
        p.categoryName DESC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge should be smaller now that the composite index is in place.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **categoryName** in descending order first, then by **name** in ascending order, and then finally by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p
    ORDER BY
        p.categoryName DESC,
        p.name ASC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge is higher again because of the complexity of the query and the lack of a supporting composite index.

1. In the **Data Explorer**, expand the **cosmicworks** database node, expand the **products** container node, and then select **Settings** again.

1. In the **Settings** tab, navigate to the **Indexing Policy** section.

1. Replace the indexing policy with this modified JSON object and then **Save** the changes:

    ```
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [
        {
          "path": "/*"
        }
      ],
      "excludedPaths": [],
      "compositeIndexes": [
        [
          {
            "path": "/categoryName",
            "order": "descending"
          },
          {
            "path": "/price",
            "order": "ascending"
          }
        ],
        [
          {
            "path": "/categoryName",
            "order": "descending"
          },
          {
            "path": "/name",
            "order": "ascending"
          },
          {
            "path": "/price",
            "order": "ascending"
          }
        ]
      ]
    }
    ```

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **categoryName** in descending order first, then by **name** in ascending order, and then finally by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.categoryName,
        p.price
    FROM
        products p
    ORDER BY
        p.categoryName DESC,
        p.name ASC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge should be lower now that a composite index is in place.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
