---
lab:
    title: 'Optimize an Azure Cosmos DB for NoSQL container''s index policy for a specific query'
    module: 'Module 10 - Optimize query and operation performance in Azure Cosmos DB for NoSQL'
---

# Optimize an Azure Cosmos DB for NoSQL container's indexing policy for a query

When planning for an Azure Cosmos DB for NoSQL account, knowing our most popular queries can help us tune the indexing policy so that queries are as performant as possible.

In this lab, we will use the Data Explorer to test SQL queries with the default indexing policy and an indexing policy that includes a composite index.

## Create an Azure Cosmos DB for NoSQL account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you will select which of the APIs you want the account to support (for example, **Mongo API** or **NoSQL API**). Once the Azure Cosmos DB for NoSQL account is done provisioning, you can retrieve the endpoint and key and use them to connect to the Azure Cosmos DB for NoSQL account using the Azure SDK for .NET or any other SDK of your choice.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB for NoSQL** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Workload Type** | **Learning** |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Data Explorer** pane.

1. In the **Data Explorer** pane, expand **New Container** and then select **New Database**.

1. In the **New Database** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *``cosmicworks``* |
    | **Provision throughput** | enabled |
    | **Database throughput** | **Manual** |
    | **Database Required RU/s** | ``1000`` |

1. Back in the **Data Explorer** pane, observe the **cosmicworks** database node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *cosmicworks* |
    | **Container id** | *``products``* |
    | **Partition key** | *``/category/name``* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

1. In the resource blade, navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Notice the **PRIMARY CONNECTION STRING** field. You will use this **connection string** value later in this exercise.

1. Open **Visual Studio Code**.

## Seed your Azure Cosmos DB for NoSQL account with sample data

You will use a command-line utility that creates a **cosmicworks** database and a **products** container. The tool will then create a set of items that you will observe using the change feed processor running in your terminal window.

1. In **Visual Studio Code**, open the **Terminal** menu and then select **New Terminal** to open a new terminal.

1. Install the [cosmicworks][nuget.org/packages/cosmicworks] command-line tool for global use on your machine.

    ```
    dotnet tool install --global CosmicWorks --version 2.3.1
    ```

    > &#128161; This command may take a couple of minutes to complete. This command will output the warning message (*Tool 'cosmicworks' is already installed') if you have already installed the latest version of this tool in the past.

1. Run cosmicworks to seed your Azure Cosmos DB account with the following command-line options:

    | **Option** | **Value** |
    | ---: | :--- |
    | **-c** | *The connection string value you checked earlier in this lab* |
    | **--number-of-employees** | *The cosmicworks command populates your database with both employees and products containers with 1000 and 200 items respectively, unless specified otherwise* |

    ```powershell
    cosmicworks -c "connection-string" --number-of-employees 0 --disable-hierarchical-partition-keys
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/** and your key is: **fDR2ci9QgkdkvERTQ==**, then the command would be:
    > ``cosmicworks -c "AccountEndpoint=https://dp420.documents.azure.com:443/;AccountKey=fDR2ci9QgkdkvERTQ==" --number-of-employees 0 --disable-hierarchical-partition-keys``

1. Wait for the **cosmicworks** command to finish populating the account with a database, container, and items.

1. Close the integrated terminal.

1. Close **Visual Studio Code** and return to your browser.

## Execute SQL queries and measure their request unit charge

Before you modify the indexing policy, first, you will run a few sample SQL queries to get a baseline request unit charge expressed in RUs.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Select **Execute Query** to run the default query:

    ```
    SELECT * FROM c
    ```

1. Observe the results of the query. Select **Query Stats** to view the request unit charge in RUs.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all three values from all documents:

    ```
    SELECT 
        p.name,
        p.category,
        p.price
    FROM
        products p    
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge is almost the same as the first query.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return three values from all documents ordered by **categoryName**:

    ```
    SELECT 
        p.name,
        p.category,
        p.price
    FROM
        products p
    ORDER BY
        p.category DESC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. The request unit charge has increased due to the **ORDER BY** clause.

## Create a composite index in the indexing policy

Now, you will need to create a composite index if you sort your items using multiple properties. In this task, you will create a composite index to sort items by their categoryName, and then their actual name.

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **products** container node, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **category** in descending order first, and then by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.category,
        p.price
    FROM
        products p
    ORDER BY
        p.category DESC,
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
            "path": "/category",
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
        p.category,
        p.price
    FROM
        products p
    ORDER BY
        p.category DESC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. This time, since the query completed, you can again review the RUs charge.

1. Delete the contents of the editor area.

1. Create a new SQL query that will order the results by the **category** in descending order first, then by **name** in ascending order, and then finally by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.category,
        p.price
    FROM
        products p
    ORDER BY
        p.category DESC,
        p.name ASC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. The query should fail with the error **The order by query does not have a corresponding composite index that it can be served from**.

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
            "path": "/category",
            "order": "descending"
          },
          {
            "path": "/price",
            "order": "ascending"
          }
        ],
        [
          {
            "path": "/category",
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

1. Create a new SQL query that will order the results by the **category** in descending order first, then by **name** in ascending order, and then finally by the **price** in ascending order:

    ```
    SELECT 
        p.name,
        p.category,
        p.price
    FROM
        products p
    ORDER BY
        p.category DESC,
        p.name ASC,
        p.price ASC
    ```

1. Select **Execute Query**.

1. Observe the results and stats of the query. This time, since the query completed, you can again review the RUs charge.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
