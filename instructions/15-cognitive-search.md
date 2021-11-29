---
lab:
    title: 'Search data using Azure Cognitive Search and Azure Cosmos DB SQL API'
    module: 'Module 7 - Integrate Azure Cosmos DB SQL API with Azure services'
---

# Search data using Azure Cognitive Search and Azure Cosmos DB SQL API

Azure Cognitive Search combines a search engine as a service with deep integration with AI capabilities to enrich the information in the search index.

In this lab, you will build an Azure Cognitive Search index that automatically indexes data in an Azure Cosmos DB SQL API container and enriches the data using the Azure Cognitive Services Translator functionality.

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

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

    1. Record the value of the **PRIMARY CONNECTION STRING** field. You will use this **connection string** value later in this exercise.

1. Select **Data Explorer** from the resource menu.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Create new* &vert; *cosmicworks* |
    | **Container id** | *products* |
    | **Partition key** | */categoryId* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

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

## Create Azure Cognitive Search resource

Before continuing with this exercise, you must first create a new Azure Cognitive Search instance.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cognitive Search*, and then create a new **Azure Cognitive Search** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Pricing tier** | *Free* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cognitive Search** account resource.

## Build indexer and index for Azure Cosmos DB SQL API data

You will create an indexer that indexes a subset of data in a specific Azure Cosmos DB SQL API container on an hourly basis.

1. From the **Azure Cognitive Search** resource blade, select **Import data**.

1. In the **Connect to your data** step of the **Import data** wizard, in the **Data Source** list, select **Azure Cosmos DB**.

1. Configure the data source with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Data source name** | *products-cosmossql-source* |
    | **Connection string** | ***connection string** of the Azure Cosmos DB SQL API account created earlier* |
    | **Database** | *cosmicworks* |
    | **Collection** | *products* |

1. In the **query** field, enter the following SQL query to create a materialized view of a subset of your data in the container:

    ```
    SELECT 
        p.id, 
        p.categoryId, 
        p.name, 
        p.price,
        p._ts
    FROM 
        products p 
    WHERE 
        p._ts > @HighWaterMark 
    ORDER BY 
        p._ts
    ```

1. Select the **Query results ordered by _ts** checkbox.

    > &#128221; This checkbox lets Azure Cognitive Search know that the query sorts results by the **_ts** field. This type of sorting enables incremental progress tracking. If the indexer fails, it can pick right back up form the same **_ts** value since the results are ordered by the timestamp.

1. Select **Next: Add cognitive skills**.

1. Select **Next: Customize target index**.

1. In the **Customize target index** step of the wizard, configure the index with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Index name** | *products-index* |
    | **Key** | *id* |

1. In the field table, configure the **Retrievable**, **Filterable**, **Sortable**, **Facetable**, and **Searchable** options for each field using the following table:

    | **Field** | **Retrievable** | **Filterable** | **Sortable** | **Facetable** | **Searchable** |
    | ---: | :---: | :---: | :---: | :---: | :---: |
    | **id** | &#10004; | &#10004; | &#10004; | | |
    | **categoryId** | &#10004; | &#10004; | &#10004; | &#10004; | |
    | **name** | &#10004; | &#10004; | &#10004; | | &#10004; (English - Microsoft) |
    | **price** | &#10004; | &#10004; | &#10004; | &#10004; | |

1. Select **Next: Create an indexer**.

1. In the **Create an indexer** step of the wizard, configure the indexer with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Name** | *products-cosmosdb-indexer* |
    | **Schedule** | *Hourly* |

1. Select **Submit** to create the data source, index, and indexer.

    > &#128221; You may be required to dismiss a survey popup after creating your first indexer.

1. From the **Azure Cognitive Search** resource blade, navigate to the **Indexers** tab to observe the result of your first indexing operation.

1. Wait for the **products-cosmosdb-indexer** indexer to have a status of **Success** before continuing with this task.

    > &#128221; You may need to use the **Refresh** option to update the blade if it does not update automatically.

1. Navigate to the **Indexes** tab and then select the **products-index** index.

## Validate index with example search queries

Now that your materialized view of the Azure Cosmos DB SQL API data is in the search index, you can perform a few basic queries that take advantage of the features in Azure Cognitive Search.

> &#128221; This lab is not intended to teach the Azure Cognitive Search syntax. These queries were curated to showcase some of the features available in the search index and engine.

1. In the **products-index** &vert; **index** pane, select **Search** to issue a default search query that returns all possible results using a **\*** (wildcard) operator.

1. Observe that this search query returns all possible results.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    touring 3000
    ```

1. Observe that this search query returns results that contain either the terms **touring** or **3000** giving a higher score to results that contains both terms. The results are then sorted in descending order by the **@search.score** field.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    red&$count=true
    ```

1. Observe that this search query returns results with the term **red**, but also now includes a metadata field indicating the total count of results even if they are not all included in the same page.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    blue&$count=true&$top=6
    ```

1. Observe that this search query only returns a set of six results at a time even though there are more matches server-side.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    mountain&$count=true&$top=25&$skip=50
    ```

1. Observe that this search query skips the first 50 results and returns a set of 25 results. If this was a paginated view in a client-side application, you could infer that this would be the third "page" of results.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    touring&$count=true&$filter=price lt 500
    ```

1. Observe that this search query only returns results where the value of the numeric price field is less than 500.

1. In the **Query string** editor, enter the following query and then select **Search**:

    ```
    road&$count=true&$top=15&facet=price,interval:500
    ```

1. Observe that this search query returns a collection of facet data that indicates how many items belong to each category even if they are not all present in the current page of results. In this example, the matching items are broken down into numeric price categories in intervals of 500. This is typically used to populate filters and navigation aids in client-side applications.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
