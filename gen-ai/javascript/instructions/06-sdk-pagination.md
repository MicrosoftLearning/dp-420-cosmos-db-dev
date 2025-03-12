---
lab:
    title: '06 - Paginate cross-product query results with the Azure Cosmos DB for NoSQL SDK'
    module: 'Author complex queries with the Azure Cosmos DB for NoSQL'
---

# Paginate cross-product query results with the Azure Cosmos DB for NoSQL SDK

Azure Cosmos DB queries will typically have multiple pages of results. Pagination is done automatically server-side when Azure Cosmos DB cannot return all query results in one single execution. In many applications, you will want to write code using the SDK to process your query results in batches in a performant manner.

In this lab, you'll create a feed iterator that can be used in a loop to iterate over your entire result set.

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

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/06-sdk-pagination** folder.

1. Open the context menu for the **javascript/06-sdk-pagination** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **javascript/06-sdk-pagination** folder.

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

When processing query results, you must make sure your code progresses through all pages of results and checks to see if any more pages are remaining before making subsequent requests.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/06-sdk-pagination** folder.

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

1. Create a new method named **paginateResults** and code to execute that method when you run the script. You will add the code to query the container within this method:

    ```javascript
    async function paginateResults() {
        // Query the container
    }

    paginateResults().catch((error) => {
        console.error(error);
    });
    ```

1. Inside the **paginateResults** method, add the following code to connect to the database and container you created earlier::

    ```javascript
    const database = client.database("cosmicworks-full");
    const container = database.container("products");
    ```

1. Create a query string variable named `sql` with a value of `SELECT * FROM products p`.

    ```javascript
    const sql = "SELECT * FROM products p";
    ```

1. Create a new variable named `options` and set it to an object with the `enableCrossPartitionQuery` property set to `true`. This property allows sending more than one request to execute the query in the Azure Cosmos DB service. More than one request is necessary if the query is not scoped to a single partition key value. Set the `maxItemCount` property to `50` to limit the number of items per page:

    ```javascript
    const options = {
        enableCrossPartitionQuery: true,
        maxItemCount: 50 // Set the maximum number of items per page
    };
    ```

1. Invoke the [`query`](https://learn.microsoft.com/javascript/api/%40azure/cosmos/items?view=azure-node-latest#@azure-cosmos-items-query-1) method with the `sql` and `options` variables as parameters to the constructor. This method returns an iterator that can be used to fetch the next page of results:

    ```javascript
    const iterator = container.items.query(query, options);
    ```

1. Iterate over the paginated results and print the `id`, `name`, and `price` of each item. The `iterator.getAsyncIterator` method returns an async iterator that can be used to fetch the `for await...of` loop to retrieve each page of results. This loop automatically handles the asynchronous iteration over the pages.

    ```javascript
    for await (const page of iterator.getAsyncIterator()) {
        page.resources.forEach(product => {
            console.log(`[${product.id}] ${product.name} $${product.price.toFixed(2)}`);
        });
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

    async function paginateResults() {
        const database = client.database("cosmicworks-full");
        const container = database.container("products");
        
        const query = "SELECT * FROM products WHERE products.price > 500";

        const options = {
            enableCrossPartitionQuery: true,
            maxItemCount: 50 // Set the maximum number of items per page
        };
        
        const iterator = container.items.query(query, options);

        for await (const page of iterator.getAsyncIterator()) {
            page.resources.forEach(product => {
                console.log(`[${product.id}] ${product.name} $${product.price.toFixed(2)}`);
            });
        }
    }
    
    paginateResults().catch((error) => {
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

1. The script will now output pages of 50 items at a time.

    > &#128161; The query will match hundreds of items in the products container.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[npmjs.com/package/@azure/cosmos]: https://www.npmjs.com/package/@azure/cosmos
[npmjs.com/package/@azure/identity]: https://www.npmjs.com/package/@azure/identity
