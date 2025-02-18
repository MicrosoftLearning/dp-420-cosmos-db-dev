---
title: '04 - Batch multiple point operations together with the Azure Cosmos DB for NoSQL SDK'
lab:
    title: '04 - Batch multiple point operations together with the Azure Cosmos DB for NoSQL SDK'
    module: 'Perform cross-document transactional operations with the Azure Cosmos DB for NoSQL'
layout: default
nav_order: 7
parent: 'Python SDK labs'
---

# Batch multiple point operations together with the Azure Cosmos DB for NoSQL SDK

The `azure-cosmos` Python SDK provides the `execute_item_batch` method for executing multiple point operations in a single logical step. This allows developers to efficiently bundle multiple operations together and determine if they completed successfully server-side.

In this lab, you'll use the Python SDK to perform dual-item batch operations that demonstrate both successful and errant transactional batches.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Create an Azure Cosmos DB for NoSQL account

If you already created an Azure Cosmos DB for NoSQL account for the **Build copilots with Azure Cosmos DB** labs on this site, you can use it for this lab and skip ahead to the [next section](#install-the-azure-cosmos-library). Otherwise, view the [Setup Azure Cosmos DB](../../common/instructions/00-setup-cosmos-db.md) instructions to create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role.

## Install the azure-cosmos library

The **azure-cosmos** library is available on **PyPI** for easy installation into your Python projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/04-sdk-batch** folder.

1. Open the context menu for the **python/04-sdk-batch** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/04-sdk-batch** folder.

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
       asyncio.run(main())
   ```

1. Your **script.py** file should now look like this:

   ```python
   from azure.cosmos import exceptions, PartitionKey
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

## Creating a transactional batch

First, let's create a simple transactional batch that makes two fictional products. This batch will insert a worn saddle and a rusty handlebar into the container with the same "used accessories" category identifier. Both items have the same logical partition key, ensuring that we will have a successful batch operation.

1. Return to **Visual Studio Code**. If it is not still open, open the **script.py** code file within the **python/04-sdk-batch** folder.

1. Create two dictionaries representing products: a **worn saddle** and a **rusty handlebar**. Both items share the same partition key value of **"9603ca6c-9e28-4a02-9194-51cdb7fea816"**.

   ```python
   saddle = ("create", (
       {"id": "0120", "name": "Worn Saddle", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
   ))

   handlebar = ("create", (
       {"id": "012A", "name": "Rusty Handlebar", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
   ))
   ```

1. Define the partition key value.

   ```python
   partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
   ```

1. Create a batch containing the two items.

   ```python
   batch = [saddle, handlebar]
   ```

1. Execute the batch using the `execute_item_batch` method of the `container` object and print the response for each item in the batch.

```python
try:
        # Execute the batch
        batch_response = await container.execute_item_batch(batch, partition_key=partition_key)

        # Print results for each operation in the batch
        for idx, result in enumerate(batch_response):
            status_code = result.get("statusCode")
            resource = result.get("resourceBody")
            print(f"Item {idx} - Status Code: {status_code}, Resource: {resource}")
    except exceptions.CosmosBatchOperationError as e:
        error_operation_index = e.error_index
        error_operation_response = e.operation_responses[error_operation_index]
        error_operation = batch[error_operation_index]
        print("Error operation: {}, error operation response: {}".format(error_operation, error_operation_response))
    except Exception as ex:
        print(f"An error occurred: {ex}")
```

1. Once you are done, your code file should now include:
  
   ```python
   from azure.cosmos import exceptions, PartitionKey
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

           saddle = ("create", (
               {"id": "0120", "name": "Worn Saddle", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
           ))
           handlebar = ("create", (
               {"id": "012A", "name": "Rusty Handlebar", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
           ))
        
           partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
        
           batch = [saddle, handlebar]
            
           try:
               # Execute the batch
               batch_response = await container.execute_item_batch(batch, partition_key=partition_key)
        
               # Print results for each operation in the batch
               for idx, result in enumerate(batch_response):
                   status_code = result.get("statusCode")
                   resource = result.get("resourceBody")
                   print(f"Item {idx} - Status Code: {status_code}, Resource: {resource}")
           except exceptions.CosmosBatchOperationError as e:
               error_operation_index = e.error_index
               error_operation_response = e.operation_responses[error_operation_index]
               error_operation = batch[error_operation_index]
               print("Error operation: {}, error operation response: {}".format(error_operation, error_operation_response))
           except Exception as ex:
               print(f"An error occurred: {ex}")

   if __name__ == "__main__":
       asyncio.run(main())
   ```

1. **Save** and run the script again:

   ```bash
   python script.py
   ```

1. The output should indicate a successful status code for each operation.

## Creating an errant transactional batch

Now, let’s create a transactional batch that will error purposefully. This batch will attempt to insert two items that have different logical partition keys. We will create a flickering strobe light in the "used accessories" category and a new helmet in the "pristine accessories" category. By definition, this should be a bad request and return an error when performing this transaction.

1. Return to the editor tab for the **script.py** code file.

1. Delete the following lines of code:

   ```python
   saddle = ("create", (
       {"id": "0120", "name": "Worn Saddle", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
   ))
   handlebar = ("create", (
       {"id": "012A", "name": "Rusty Handlebar", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
   ))

   partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"

   batch = [saddle, handlebar]
   ```

1. Modify the script to create a new **flickering strobe light** and a **new helmet** with different partition key values.

   ```python
   light = ("create", (
       {"id": "012B", "name": "Flickering Strobe Light", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
   ))
   helmet = ("create", (
       {"id": "012C", "name": "New Helmet", "categoryId": "0feee2e4-687a-4d69-b64e-be36afc33e74"},
   ))
   ```

1. Define the partition key value for the batch.

   ```python
   partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
   ```

1. Create a new batch containing the two items.

   ```python
   batch = [light, helmet]
   ```

1. Once you are done, your code file should now include:

   ```python
   from azure.cosmos import exceptions, PartitionKey
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

           light = ("create", (
               {"id": "012B", "name": "Flickering Strobe Light", "categoryId": "9603ca6c-9e28-4a02-9194-51cdb7fea816"},
           ))
           helmet = ("create", (
               {"id": "012C", "name": "New Helmet", "categoryId": "0feee2e4-687a-4d69-b64e-be36afc33e74"},
           ))
        
           partition_key = "9603ca6c-9e28-4a02-9194-51cdb7fea816"
        
           batch = [light, helmet]
            
           try:
               # Execute the batch
               batch_response = await container.execute_item_batch(batch, partition_key=partition_key)
        
               # Print results for each operation in the batch
               for idx, result in enumerate(batch_response):
                   status_code = result.get("statusCode")
                   resource = result.get("resourceBody")
                   print(f"Item {idx} - Status Code: {status_code}, Resource: {resource}")
           except exceptions.CosmosBatchOperationError as e:
               error_operation_index = e.error_index
               error_operation_response = e.operation_responses[error_operation_index]
               error_operation = batch[error_operation_index]
               print("Error operation: {}, error operation response: {}".format(error_operation, error_operation_response))
           except Exception as ex:
               print(f"An error occurred: {ex}")

   if __name__ == "__main__":
       asyncio.run(main())
    ```

1. **Save** and run the script again:

   ```bash
   python script.py
   ```

1. Observe the output from the terminal. The status code on the second item (the "New Helmet") should be **400** for **Bad Request**. This occurred because all items within the transaction did not share the same partition key value as the transactional batch.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
[pypi.org/project/azure-identity]: https://pypi.org/project/azure-identity
