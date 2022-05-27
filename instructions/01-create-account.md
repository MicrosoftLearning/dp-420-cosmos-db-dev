---
lab:
    title: 'Create an Azure Cosmos DB SQL API account'
    module: 'Module 1 - Get started with Azure Cosmos DB SQL API'
---

# Create an Azure Cosmos DB SQL API account

Before diving too deeply into Azure Cosmos DB, it's important to get a handle on the basics of creating the resources you will use the most. In most scenarios, you will need to be comfortable creating accounts, databases, containers, and items. In a real-world scenario, you should also have a few basic queries "on hand" to test that you created all of your resources correctly.

In this lab, you'll create a new Azure Cosmos DB account using the SQL API. You will then use the Data Explorer to create a database, a container, and two items. Finally, you will query the database for the items you created.

## Create a new Azure Cosmos DB account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you will select which of the APIs you want the account to support (for example, **Mongo API** or **SQL API**).

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Within the **Azure services** category, select **Create a resource**, and then select **Azure Cosmos DB**.

    > &#128161; Alternatively; expand the **&#8801;** menu, select **All Services**, in the **Databases** category, select **Azure Cosmos DB**, and then select **Create**.

1. In the **Select API option** pane, select the **Create** option within the **Core (SQL) - Recommended** section.

1. Within the **Create Azure Cosmos DB Account** pane, observe the **Basics** tab.

1. On the **Basics** tab, enter the following values for each setting:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Subscription** | *All resources must belong to a resource group. Every resource group must belong to a subscription. Here, use your existing Azure subscription.* |
    | **Resource Group** | *All resources must belong to a resource group. Here, select an existing or create a new resource group.* |
    | **Account Name** | *The globally unique account name. This name will be used as part of the DNS address for requests. Enter any globally unique name. The portal will check the name in real time.* |
    | **Location** | *Select the geographical region from which your database will initially be hosted. Choose any available region.* |
    | **Capacity mode** | *Select provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

1. Select **Review + Create** to navigate to the **Review + Create** tab, and then select **Create**.

    > &#128221; It can take 10-15 minutes for the Azure Cosmos DB SQL API account to be ready for use.

1. Observe the **Deployment** pane. When the deployment is complete, the pane will update with a **Deployment successful** message.

1. Still within the **Deployment** pane, select **Go to resource**.

## Use the Data Explorer to create a new database and container

The Data Explorer will be your primary tool to manage the Azure Cosmos DB SQL API database and containers in the Azure portal. You will create a basic database and container to use in this lab.

1. From within the **Azure Cosmos DB account** pane, select **Data Explorer** from the resource menu.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *cosmicworks* |
    | **Share throughput across containers** | *Do not select* |
    | **Container id** | *products* |
    | **Partition key** | */categoryId* |
    | **Container throughput (autoscale)** | *Manual* |
    | **RU/s** | *400* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

## Use the Data Explorer to create new items

The Data Explorer also includes a suite of features to query, create, and manage items in an Azure Cosmos DB SQL API container. You will create two basic items using raw JSON in the Data Explorer.

1. In the **Data Explorer** pane, expand the **cosmicworks** database node, expand the **products** container node, and then select **Items**.

1. Still in the **Data Explorer** pane, select **New Item** from the command bar. In the editor, replace the placeholder JSON item with the following content:

    ```
    {
      "categoryId": "4F34E180-384D-42FC-AC10-FEC30227577F",
      "categoryName": "Components, Pedals",
      "sku": "PD-R563",
      "name": "ML Road Pedal",
      "price": 62.09
    }
    ```

1. Select **Save** from the command bar to add the first JSON item:

1. Back in the **Items** tab, select **New Item** from the command bar. In the editor, replace the placeholder JSON item with the following content:

    ```
    {
      "categoryId": "75BF1ACB-168D-469C-9AA3-1FD26BB4EA4C",
      "categoryName": "Bikes, Touring Bikes",
      "sku": "BK-T18Y-44",
      "name": "Touring-3000 Yellow, 44",
      "price": 742.35
    }
    ```

1. Select **Save** from the command bar to add the second JSON item:

1. In the **Items** tab, observe the two new items in the **Items** pane.

## Use the Data Explorer to issue a basic query

Finally, the Data Explorer has a built-in query editor that is used to issue queries, observe the results, and measure impact in terms of request units per second (RU/s).

1. In the **Data Explorer** pane, select **New SQL Query**.

1. In the query tab, select **Execute Query** to view a standard query that selects all items without any filters.

1. Delete the contents of the editor area.

1. In the **Query** tab, replace the placeholder query with the following content:

    ```
    SELECT * FROM products p WHERE p.price > 500
    ```

    > &#128221; This query will select all items where the **price** is greater than $500.

1. Select **Execute Query**.

1. Observe the results of the query, which should include a single JSON item and all of its properties.

1. In the **Query** tab, select **Query Stats**.

1. Still in the **Query** tab, observe the value of the **Request Charge** field within the **Query Statistics** section.

    > &#128221; Typically, the request charge for this simple query is between 2 and 3 RU/s when the container size is small.

1. Close your web browser window or tab.
