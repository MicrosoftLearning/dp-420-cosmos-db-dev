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

If you already created an Azure Cosmos DB database named **cosmicworks-full** and container within it named **products**, which is preloaded with sample data, you can use it for this lab and skip ahead to the [next section](#install-the-azure-cosmos-library). Otherwise, follow the steps below to create a new sample database and container.

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

## Install the azure-cosmos library

The **azure-cosmos** library is available on **PyPI** for easy installation into your Python projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/06-sdk-pagination** folder.

1. Open the context menu for the **python/06-sdk-pagination** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/06-sdk-pagination** folder.

1. Create and activate a virtual environment to manage dependencies:

   ```bash
   python -m venv venv
   source venv/bin/activate   # On Windows, use `venv\Scripts\activate`
   ```

1. Install the [azure-cosmos][pypi.org/project/azure-cosmos] package using the following command:

   ```bash
   pip install azure-cosmos
   ```

1. Since we are using the asynchronous version of the SDK, we need to install the `asyncio` library as well:

   ```bash
   pip install asyncio
   ```

1. The asynchronous version of the SDK also requires the `aiohttp` library. Install it using the following command:

   ```bash
   pip install aiohttp
   ```

1. Install the [azure-identity][pypi.org/project/azure-identity] library, which allows us to use Azure authentication to connect to the Azure Cosmos DB workspace, using the following command:

   ```bash
   pip install azure-identity
   ```

## Paginate through small result sets of a SQL query using the SDK

When processing query results, you must make sure your code progresses through all pages of results and checks to see if any more pages are remaining before making subsequent requests.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/06-sdk-pagination** folder.

1. Open the blank Python file named **script.py**.

1. Add the following `import` statements to import the asynchronous **CosmosClient** class, **DefaultAzureCredential** class, and the **asyncio** library:

   ```python
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio
   ```

1. Add variables named **endpoint** and **credential** and set the **endpoint** value to the **endpoint** of the Azure Cosmos DB account you created earlier. The **credential** variable should be set to a new instance of the **DefaultAzureCredential** class:

   ```python
   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()
   ```

    > &#128221; For example, if your endpoint is: **https://dp420.documents.azure.com:443/**, the statement would be: **endpoint = "https://dp420.documents.azure.com:443/"**.

1. All interaction with Cosmos DB starts with an instance of the `CosmosClient`. In order to use the asynchronous client, we need to use async/await keywords, which can only be used within async methods. Create a new async method named **main** and add the following code to create a new instance of the asynchronous **CosmosClient** class using the **endpoint** and **credential** variables:

   ```python
   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
   ```

    > &#128161; Since we're using the asynchronous **CosmosClient** client, in order to properly use it you also have to warm it up and close it down. We recommend using the `async with` keywords as demonstrated in the code above to start your clients - these keywords create a context manager that automatically warms up, initializes, and cleans up the client, so you don't have to.

1. Add the following code to connect to the database and container you created earlier:

   ```python
   database = client.get_database_client("cosmicworks-full")
   container = database.get_container_client("products")
   ```

1. Create a new variable named **sql** of type *string* with a value of **SELECT * FROM products WHERE products.price > 500**:

   ```python
   sql = "SELECT * FROM products WHERE products.price > 500"
   ```

1. Invoke the [`query_items`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-query-items) method with the `sql` variable as a parameter to the constructor. Set the `max_item_count` to `50` to limit the number of items returned in each page.

   ```python
   iterator = container.query_items(
       query=sql,
       max_item_count=50  # Set maximum items per page
   )
   ```

1. Create an async **for** loop that asynchronously invokes the [`by_page`](https://learn.microsoft.com/python/api/azure-core/azure.core.paging.itempaged?view=azure-python#azure-core-paging-itempaged-by-page) method on the iterator object. This method returns a page of results each time it is called.

   ```python
   async for page in iterator.by_page():
   ```

1. Within the async **for** loop, asynchronously iterate over the paginated results and print the `id`, `name`, and `price` of each item.

   ```python
   async for product in page:
       print(f"[{product['id']}]	{product['name']}	${product['price']:.2f}")
   ```

1. Underneath the `main` method, add the following code to run the `main` method using the `asyncio` library:

   ```python
   if __name__ == "__main__":
       asyncio.run(query_items_async())
   ```

1. Your **script.py** file should now look like this:

   ```python
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
           # Get database and container clients
           database = client.get_database_client("cosmicworks-full")
           container = database.get_container_client("products")
    
           sql = "SELECT * FROM products WHERE products.price > 500"
        
           iterator = container.query_items(
               query=sql,
               max_item_count=50  # Set maximum items per page
           )
        
           async for page in iterator.by_page():
               async for product in page:
                   print(f"[{product['id']}]	{product['name']}	${product['price']:.2f}")

   if __name__ == "__main__":
       asyncio.run(main())
   ```

1. **Save** the **script.py** file.

1. Before running the script, you must log into Azure using the `az login` command. At the terminal window, run:

   ```bash
   az login
   ```

1. Run the script to create the database and container:

   ```bash
   python script.py
   ```

1. The script will now output pages of 50 items at a time.

    > &#128161; The query will match hundreds of items in the products container.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
[pypi.org/project/azure-identity]: https://pypi.org/project/azure-identity
