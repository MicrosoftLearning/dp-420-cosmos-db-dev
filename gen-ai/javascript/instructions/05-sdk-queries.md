---
title: '05 - Execute a query with the Azure Cosmos DB for NoSQL SDK'
lab:
    title: '05 - Execute a query with the Azure Cosmos DB for NoSQL SDK'
    module: 'Query the Azure Cosmos DB for NoSQL'
layout: default
nav_order: 8
parent: 'JavaScript SDK labs'
---

# Execute a query with the Azure Cosmos DB for NoSQL SDK

The latest version of the JavaScript SDK for Azure Cosmos DB for NoSQL simplifies querying a container and iterating over result sets using JavaScript's modern features.

The `@azure/cosmos` library has built-in functionality to make querying Azure Cosmos DB efficient and straightforward.

In this lab, you'll use an iterator to process a large result set returned from Azure Cosmos DB for NoSQL. You will use the JavaScript SDK to query and iterate over results.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Create an Azure Cosmos DB for NoSQL account

If you already created an Azure Cosmos DB for NoSQL account for the **Build copilots with Azure Cosmos DB** labs on this site, you can use it for this lab and skip ahead to the [next section](#create-azure-cosmos-db-database-and-container-with-sample-data). Otherwise, view the [Setup Azure Cosmos DB](../../common/instructions/00-setup-cosmos-db.md) instructions to create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role.

## Create Azure Cosmos DB database and container with sample data

If you already created an Azure Cosmos DB database named **cosmicworks-full** and container within it named **products**, which is preloaded with sample data, you can use it for this lab and skip ahead to the [next section](#import-the-azurecosmos-library). Otherwise, follow the steps below to create a new sample database and container.

<details markdown=1>
<summary markdown="span"><strong>Click to expand/collapse steps to create database and container with sample data</strong></summary>

1. Within the newly created **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, select **Launch quick start** on the home page.

1. Within the **New Container** form, enter the following values:

    - **Database id**: `cosmicworks-full`
    - **Container id**: `products`
    - **Partition key**: `/categoryId`
    - **Analytical store**: `Off`

1. Select **OK** to create the new container. This process will take a minute or two while it creates the resources and preloads the container with sample product data.

1. Keep the browser tab open, as we will return to it later.

1. Switch back to **Visual Studio Code**.

</details>

## Import the @azure/cosmos library

The **@azure/cosmos** library is available on **npm** for easy installation into your JavaScript projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/05-sdk-queries** folder.

1. Open the context menu for the **javascript/05-sdk-queries** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **javascript/05-sdk-queries** folder.

1. Initialize a new Node.js project:

    ```bash
    npm init -y
    ```

1. Install the [@azure/cosmos][npmjs.com/package/@azure/cosmos] package using the following command:

    ```bash
    npm install @azure/cosmos
    ```

1. Install the [@azure/identity][npmjs.com/package/@azure/identity] library, which allows us to use Azure authentication to connect to the Azure Cosmos DB workspace, using the following command:

    ```bash
    npm install @azure/identity
    ```

## Iterate over the results of a SQL query using the SDK

Using the credentials from the newly created account, you will connect with the SDK classes and connect to the database and container you provisioned in an earlier step, and iterate over the results of a SQL query using the SDK.

You will now use an iterator to create a simple-to-understand loop over paginated results from Azure Cosmos DB. Behind the scenes, the SDK will manage the feed iterator and ensure subsequent requests are invoked correctly.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/05-sdk-queries** folder.

1. Open the empty JavaScript file named **script.js**.

1. Add the following `require` statements to import the **@azure/cosmos** and **@azure/identity** libraries:

    ```javascript
    const { CosmosClient } = require("@azure/cosmos");
    const { DefaultAzureCredential  } = require("@azure/identity");
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0
    ```

1. Add variables named **endpoint** and **credential** and set the **endpoint** value to the **endpoint** of the Azure Cosmos DB account you created earlier. The **credential** variable should be set to a new instance of the **DefaultAzureCredential** class:

    ```javascript
    const endpoint = "<cosmos-endpoint>";
    const credential = new DefaultAzureCredential();
    ```

    > &#128221; For example, if your endpoint is: **https://dp420.documents.azure.com:443/**, the statement would be: **const endpoint = "https://dp420.documents.azure.com:443/";**.

1. Add a new variable named **client** and initialize it as a new instance of the **CosmosClient** class using the **endpoint** and **credential** variables:

    ```javascript
    const client = new CosmosClient({ endpoint, aadCredentials: credential });
    ```

1. Create a new method named **queryContainer** and code to execute that method when you run the script. You will add the code to query the container within this method:

    ```javascript
    async function queryContainer() {
        // Query the container
    }

    queryContainer().catch((error) => {
        console.error(error);
    });
    ```

1. Inside the **queryContainer** method, add the following code to connect to the database and container you created earlier::

    ```javascript
    const database = client.database("cosmicworks-full");
    const container = database.container("products");
    ```

1. Create a query string variable named `sql` with a value of `SELECT * FROM products p`.

    ```javascript
    const sql = "SELECT * FROM products p";
    ```

1. Invoke the [`query`](https://learn.microsoft.com/javascript/api/%40azure/cosmos/items?view=azure-node-latest#@azure-cosmos-items-query-1) method with the `sql` variable as a parameter to the constructor. The `enableCrossPartitionQuery` parameter, when set to `true`, allows sending more than one request to execute the query in the Azure Cosmos DB service. More than one request is necessary if the query is not scoped to a single partition key value.

    ```javascript
    const iterator = container.items.query(
        query,
        { enableCrossPartitionQuery: true }
    );
    ```

1. Iterate over the paginated results and print the `id`, `name`, and `price` of each item:

    ```javascript
    while (iterator.hasMoreResults()) {
        const { resources } = await iterator.fetchNext();
        for (const item of resources) {
            console.log(`[${item.id}]	${item.name.padEnd(35)}	${item.price.toFixed(2)}`);
        }
    }
    ```

1. Your **script.js** file should now look like this:

    ```javascript
    const { CosmosClient } = require("@azure/cosmos");
    const { DefaultAzureCredential  } = require("@azure/identity");
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0

    const endpoint = "<cosmos-endpoint>";
    const credential = new DefaultAzureCredential();

    const client = new CosmosClient({ endpoint, aadCredentials: credential });

    async function queryContainer() {
        const database = client.database("cosmicworks-full");
        const container = database.container("products");
        
        const query = "SELECT * FROM products p";
    
        const iterator = container.items.query(
            query,
            { enableCrossPartitionQuery: true }
        );
        
        while (iterator.hasMoreResults()) {
            const { resources } = await iterator.fetchNext();
            for (const item of resources) {
                console.log(`[${item.id}]	${item.name.padEnd(35)}	${item.price.toFixed(2)}`);
            }
        }
    }
    
    queryContainer().catch((error) => {
        console.error(error);
    });
    ```

1. **Save** the **script.js** file.

1. Before running the script, you must log into Azure using the `az login` command. At the terminal window, run:

    ```bash
    az login
    ```

1. Run the script to create the database and container:

    ```bash
    node script.js
    ```

1. The script will now output every product in the container.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[npmjs.com/package/@azure/cosmos]: https://www.npmjs.com/package/@azure/cosmos
[npmjs.com/package/@azure/identity]: https://www.npmjs.com/package/@azure/identity
