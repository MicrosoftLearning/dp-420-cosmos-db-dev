---
title: '05 - Execute a query with the Azure Cosmos DB for NoSQL SDK'
lab:
    title: '05 - Execute a query with the Azure Cosmos DB for NoSQL SDK'
    module: 'Query the Azure Cosmos DB for NoSQL'
layout: default
nav_order: 8
parent: 'Python SDK labs'
---

# Execute a query with the Azure Cosmos DB for NoSQL SDK

The latest version of the Python SDK for Azure Cosmos DB for NoSQL simplifies querying a container and iterating over result sets using Python's modern features.

The `azure-cosmos` library has built-in functionality to make querying Azure Cosmos DB efficient and straightforward.

In this lab, you'll use an iterator to process a large result set returned from Azure Cosmos DB for NoSQL. You will use the Python SDK to query and iterate over results.

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

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/05-sdk-queries** folder.

1. Open the context menu for the **python/05-sdk-queries** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/05-sdk-queries** folder.

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

## Iterate over the results of a SQL query using the SDK

Using the credentials from the newly created account, you will connect with the SDK classes and connect to the database and container you provisioned in an earlier step, and iterate over the results of a SQL query using the SDK.

You will now use an iterator to create a simple-to-understand loop over paginated results from Azure Cosmos DB. Behind the scenes, the SDK will manage the feed iterator and ensure subsequent requests are invoked correctly.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/05-sdk-queries** folder.

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

1. Create a query string variable named `sql` with a value of `SELECT * FROM products p`.

   ```python
   sql = "SELECT * FROM products p"
   ```

1. Invoke the [`query_items`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-query-items) method with the `sql` variable as a parameter to the constructor.

   ```python
   result_iterator = container.query_items(
       query=sql
   )
   ```

1. The **query_items** method returned an asynchronous iterator that we store in a variable named `result_iterator`. This means that each object from the iterator is an awaitable object and does not yet contain the query result. Add the code below to create an async **for** loop to await each query result as you iterate over the asynchronous iterator and print the `id`, `name`, and `price` of each item.

   ```python
   # Perform the query asynchronously
   async for item in result_iterator:
       print(f"[{item['id']}]	{item['name']}	${item['price']:.2f}")
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

           database = client.get_database_client("cosmicworks-full")
           container = database.get_container_client("products")
    
           sql = "SELECT * FROM products p"
            
           result_iterator = container.query_items(
               query=sql
           )
            
           # Perform the query asynchronously
           async for item in result_iterator:
               print(f"[{item['id']}]	{item['name']}	${item['price']:.2f}")

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

1. The script will now output every product in the container.

## Perform a query within a logical partition

In the previous section, you queried all items in the container. By default, the async **CosmosClient** performs cross-partition queries. Because of this, the query you executed (`"SELECT * FROM products p"`) caused the query engine to scan all partitions in the container. As a best practice, you should always query within a logical partition to avoid cross-partition queries. Doing so ultimately saves you money and improves performance.

In this section, you will perform a query within a logical partition by including the partition key in the query.

1. Return to the editor tab for the **script.py** code file.

1. Delete the following lines of code:

   ```python
   result_iterator = container.query_items(
       query=sql
   )
    
   # Perform the query asynchronously
   async for item in result_iterator:
       print(f"[{item['id']}]	{item['name']}	${item['price']:.2f}")
   ```

1. Modify the script to create a **partition_key** variable to store the Category ID value for jerseys. Add the **partition_key** as a parameter to the **query_items** method. This ensures that the query is executed within the logical partition for the jerseys category.

   ```python
   partition_key = "C3C57C35-1D80-4EC5-AB12-46C57A017AFB"

   result_iterator = container.query_items(
       query=sql,
       partition_key=partition_key
   )
   ```

1. In the previous section, you performed an async for loop directly on the asynchronous iterator (`async for item in result_iterator:`). This time, you'll  asynchronously create a complete list of the actual query results. This code performs the same action as the for-loop example you previously used. Add the following lines of code to create a list of results and print the results:

   ```python
   item_list = [item async for item in result_iterator]

   for item in item_list:
       print(f"[{item['id']}]	{item['name']}	${item['price']:.2f}")
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

           database = client.get_database_client("cosmicworks-full")
           container = database.get_container_client("products")
    
           sql = "SELECT * FROM products p"
            
           partition_key = "C3C57C35-1D80-4EC5-AB12-46C57A017AFB"

           result_iterator = container.query_items(
               query=sql,
               partition_key=partition_key
           )
    
           # Perform the query asynchronously
           item_list = [item async for item in result_iterator]
    
           for item in item_list:
               print(f"[{item['id']}]	{item['name']}	${item['price']:.2f}")

   if __name__ == "__main__":
       asyncio.run(main())
   ```

1. **Save** the **script.py** file.

1. Run the script to create the database and container:

   ```bash
   python script.py
   ```

1. The script will now output every product within the jersey category, effectively performing an in-partition query.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
[pypi.org/project/azure-identity]: https://pypi.org/project/azure-identity
