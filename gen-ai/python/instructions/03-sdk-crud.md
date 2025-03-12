---
lab:
    title: '03 - Create and update documents with the Azure Cosmos DB for NoSQL SDK'
    module: 'Implement Azure Cosmos DB for NoSQL point operations'
---

# Create and update documents with the Azure Cosmos DB for NoSQL SDK

The `azure-cosmos` library includes methods to create, retrieve, update, and delete (CRUD) items within an Azure Cosmos DB for NoSQL container. Together, these methods perform some of the most common "CRUD" operations across various items within NoSQL API containers.

In this lab, you'll use the Python SDK to perform everyday CRUD operations on an item within an Azure Cosmos DB for NoSQL container.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Create an Azure Cosmos DB for NoSQL account

If you already created an Azure Cosmos DB for NoSQL account for the **Build copilots with Azure Cosmos DB** labs on this site, you can use it for this lab and skip ahead to the [next section](#install-the-azure-cosmos-library). Otherwise, view the [Setup Azure Cosmos DB](../../common/instructions/00-setup-cosmos-db.md) instructions to create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role.

## Install the azure-cosmos library

The **azure-cosmos** library is available on **PyPI** for easy installation into your Python projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/03-sdk-crud** folder.

1. Open the context menu for the **python/03-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/03-sdk-crud** folder.

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

## Use the azure-cosmos library

Using the credentials from the newly created account, you will connect with the SDK classes and create a new database and container instance. Then, you will use the Data Explorer to validate that the instances exist in the Azure portal.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/03-sdk-crud** folder.

1. Open the blank Python file named **script.py**.

1. Add the following `import` statement to import the **PartitionKey** class:

   ```python
   from azure.cosmos import PartitionKey
   ```

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

1. Add the following code to create a database and container if they do not already exist:

   ```python
   # Create database
   database = await client.create_database_if_not_exists(id="cosmicworks")
    
   # Create container
   container = await database.create_container_if_not_exists(
       id="products",
       partition_key=PartitionKey(path="/categoryId"),
       offer_throughput=400
   )
   ```

1. Underneath the `main` method, add the following code to run the `main` method using the `asyncio` library:

   ```python
   if __name__ == "__main__":
       asyncio.run(query_items_async())
   ```

1. Your **script.py** file should now look like this:

   ```python
   from azure.cosmos import PartitionKey
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
           # Create database
           database = await client.create_database_if_not_exists(id="cosmicworks")
    
           # Create container
           container = await database.create_container_if_not_exists(
               id="products",
               partition_key=PartitionKey(path="/categoryId")
           )

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

1. Switch to your web browser window.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **NOSQL API** navigation tree.

## Perform create and read point operations on items with the SDK

You will now use the set of methods in the **ContainerProxy** class to perform common operations on items within a NoSQL API container.

1. Return to **Visual Studio Code**. If it is not still open, open the **script.py** code file within the **python/03-sdk-crud** folder.

1. Create a new product item and assign it to a variable named **saddle** with the following properties:

    | Property | Value |
    | ---: | :--- |
    | **id** | *706cd7c6-db8b-41f9-aea2-0e0c7e8eb009* |
    | **categoryId** | *9603ca6c-9e28-4a02-9194-51cdb7fea816* |
    | **name** | *Road Saddle* |
    | **price** | *45.99d* |
    | **tags** | *{ tan, new, crisp }* |

   ```python
   saddle = {
       "id": "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
       "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816",
       "name": "Road Saddle",
       "price": 45.99,
       "tags": ["tan", "new", "crisp"]
   }
   ```

1. Invoke the [`create_item`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-create-item) method of the **container** variable passing in the **saddle** variable as the method parameter:

   ```python
   await container.create_item(body=saddle)
   ```

1. Once you are done, your code file should now include:
  
   ```python
   from azure.cosmos import PartitionKey
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
           # Create database
           database = await client.create_database_if_not_exists(id="cosmicworks")
    
           # Create container
           container = await database.create_container_if_not_exists(
               id="products",
               partition_key=PartitionKey(path="/categoryId")
           )
        
           saddle = {
               "id": "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
               "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816",
               "name": "Road Saddle",
               "price": 45.99,
               "tags": ["tan", "new", "crisp"]
           }
            
           await container.create_item(body=saddle)

   if __name__ == "__main__":
       asyncio.run(main())
   ```

1. **Save** and run the script again:

   ```bash
   python script.py
   ```

1. Observe the new item in the **Data Explorer**.

1. Return to **Visual Studio Code**.

1. Return to the editor tab for the **script.py** code file.

1. Delete the following lines of code:

   ```python
   saddle = {
       "id": "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
       "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816",
       "name": "Road Saddle",
       "price": 45.99,
       "tags": ["tan", "new", "crisp"]
   }
    
   await container.create_item(body=saddle)
   ```

1. Create a string variable named **item_id** with a value of **706cd7c6-db8b-41f9-aea2-0e0c7e8eb009**:

   ```python
   item_id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009"
   ```

1. Create a string variable named **partition_key** with a value of **9603ca6c-9e28-4a02-9194-51cdb7fea816**:

   ```python
   partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
   ```

1. Invoke the [`read_item`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-read-item) method of the **container** variable passing in the **item_id** and **partition_key** variables as the method parameters:

   ```python
   # Read item    
   saddle = await container.read_item(item=item_id, partition_key=partition_key)
   ```

    > &#128161; The `read_item` method allows you to perform a point read operation on an item in the container. The method requires the `item_id` and `partition_key` parameters to identify the item to read. As opposed to executing a query using Cosmos DB's SQL query language to find the single item, the `read_item` method is more efficient and cost-effective way to retrieve a single item. Point reads can read the data directly and don't require the query engine to process the request.

1. Print the saddle object using a formatted output string:

   ```python
   print(f'[{saddle["id"]}]\t{saddle["name"]} ({saddle["price"]})')
   ```

1. Once you are done, your code file should now include:

   ```python
   from azure.cosmos import PartitionKey
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
           # Create database
           database = await client.create_database_if_not_exists(id="cosmicworks")
    
           # Create container
           container = await database.create_container_if_not_exists(
               id="products",
               partition_key=PartitionKey(path="/categoryId")
           )
       
           item_id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009"
           partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
   
           # Read item
           saddle = await container.read_item(item=item_id, partition_key=partition_key)
            
           print(f'[{saddle["id"]}]\t{saddle["name"]} ({saddle["price"]})')

   if __name__ == "__main__":
       asyncio.run(main())
   ```

1. **Save** and run the script again:

   ```bash
   python script.py
   ```

1. Observe the output from the terminal. Specifically, observe the formatted output text with the id, name, and price from the item.

## Perform update and delete point operations with the SDK

While learning the SDK, it's not uncommon to use an online Azure Cosmos DB account or the emulator to update an item and oscillate back-and-forth between the Data Explorer and your IDE of choice as you perform an operation and check to see if your change has been applied. Here, you will do just that as you update and delete an item using the SDK.

1. Return to your web browser window or tab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **NOSQL API** navigation tree.

1. Select the **Items** node. Select the only item within the container and then observe the values of the **name** and **price** properties of the item.

    | **Property** | **Value** |
    | ---: | :--- |
    | **Name** | *Road Saddle* |
    | **Price** | *$45.99* |

    > &#128221; At this point in time, these values should not have been changed since you have created the item. You will change these values in this exercise.

1. Return to **Visual Studio Code**. Return to the editor tab for the **script.py** code file.

1. Delete the following line of code:

   ```python
   print(f'[{saddle["id"]}]\t{saddle["name"]} ({saddle["price"]})')
   ```

1. Change the **saddle** variable by setting the value of the price property to **32.55**:

   ```python
   saddle["price"] = 32.55
   ```

1. Modify the **saddle** variable again by setting the value of the **name** property to **Road LL Saddle**:

   ```python
   saddle["name"] = "Road LL Saddle"
   ```

1. Invoke the [`replace_item`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-replace-item) method of the **container** variable passing in the **item_id** and **saddle** variables as method parameters:

   ```python
   await container.replace_item(item=item_id, body=saddle)
   ```

1. Once you are done, your code file should now include:

   ```python
   from azure.cosmos import PartitionKey
   from azure.cosmos.aio import CosmosClient
   from azure.identity.aio import DefaultAzureCredential
   import asyncio

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   async def main():
       async with CosmosClient(endpoint, credential=credential) as client:
           # Create database
           database = await client.create_database_if_not_exists(id="cosmicworks")
    
           # Create container
           container = await database.create_container_if_not_exists(
               id="products",
               partition_key=PartitionKey(path="/categoryId")
           )
        
           item_id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009"
           partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
    
           # Read item
           saddle = await container.read_item(item=item_id, partition_key=partition_key)
            
           saddle["price"] = 32.55
           saddle["name"] = "Road LL Saddle"
    
           await container.replace_item(item=item_id, body=saddle)

   if __name__ == "__main__":
       asyncio.run(main())
    ```

1. **Save** and run the script again:

   ```bash
   python script.py
   ```

1. Return to your web browser window or tab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **NOSQL API** navigation tree.

1. Select the **Items** node. Select the only item within the container and then observe the values of the **name** and **price** properties of the item.

    | **Property** | **Value** |
    | ---: | :--- |
    | **Name** | *Road LL Saddle* |
    | **Price** | *$32.55* |

    > &#128221; At this point in time, these values should  have been changed since you have observed the item.

1. Return to **Visual Studio Code**. Return to the editor tab for the **script.py** code file.

1. Delete the following lines of code:

   ```python
   # Read item
   saddle = await container.read_item(item=item_id, partition_key=partition_key)
    
   saddle["price"] = 32.55
   saddle["name"] = "Road LL Saddle"
    
   await container.replace_item(item=item_id, body=saddle)
   ```

1. Invoke the [`delete_item`](https://learn.microsoft.com/python/api/azure-cosmos/azure.cosmos.container.containerproxy?view=azure-python#azure-cosmos-container-containerproxy-delete-item) method of the **container** variable passing in the **item_id** and **partition_key** variables as method parameters:

   ```python
   # Delete the item
   await container.delete_item(item=item_id, partition_key=partition_key)
   ```

1. Save and run the script again:

   ```bash
   python script.py
   ```

1. Close the integrated terminal.

1. Return to your web browser window or tab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **NOSQL API** navigation tree.

1. Select the **Items** node. Observe that the items list is now empty.

1. Close your web browser window or tab.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
[pypi.org/project/azure-identity]: https://pypi.org/project/azure-identity
