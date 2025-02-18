---
title: '01 - Connect to Azure Cosmos DB for NoSQL with the SDK'
lab:
    title: '01 - Connect to Azure Cosmos DB for NoSQL with the SDK'
    module: 'Use the Azure Cosmos DB for NoSQL SDK'
layout: default
nav_order: 4
parent: 'Python SDK labs'
---

# Connect to Azure Cosmos DB for NoSQL with the SDK

The Azure SDK for Python is a suite of client libraries that provides a consistent developer interface to interact with many Azure services. Client libraries are packages that you would use to consume these resources and interact with them.

In this lab, you'll connect to an Azure Cosmos DB for NoSQL account using the Azure SDK for Python.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Create an Azure Cosmos DB for NoSQL account

If you already created an Azure Cosmos DB for NoSQL account for the **Build copilots with Azure Cosmos DB** labs on this site, you can use it for this lab and skip ahead to the [next section](#install-the-azure-cosmos-library). Otherwise, view the [Setup Azure Cosmos DB](../../common/instructions/00-setup-cosmos-db.md) instructions to create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role.

## Install the azure-cosmos library

The **azure-cosmos** library is available on **PyPI** for easy installation into your Python projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/01-sdk-connect** folder.

1. Open the context menu for the **python/01-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/01-sdk-connect** folder.

1. Create and activate a virtual environment to manage dependencies:

   ```bash
   python -m venv venv
   source venv/bin/activate   # On Windows, use `venv\Scripts\activate`
   ```

1. Install the [azure-cosmos][pypi.org/project/azure-cosmos] package using the following command:

   ```bash
   pip install azure-cosmos
   ```

1. Install the [azure-identity][pypi.org/project/azure-identity] library, which allows us to use Azure authentication to connect to the Azure Cosmos DB workspace, using the following command:

   ```bash
   pip install azure-identity
   ```

1. Close the integrated terminal.

## Use the azure-cosmos library

Once the Azure Cosmos DB library from the Azure SDK for Python has been imported, you can immediately use its classes to connect to an Azure Cosmos DB for NoSQL account. The **CosmosClient** class is the core class used to make the initial connection to an Azure Cosmos DB for NoSQL account.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/01-sdk-connect** folder.

1. Open the blank Python file named **script.py**.

1. Add the following `import` statement to import the **CosmosClient** and the **DefaultAzureCredential** classes:

   ```python
   from azure.cosmos import CosmosClient
   from azure.identity import DefaultAzureCredential
   ```

1. Add variables named **endpoint** and **credential** and set the **endpoint** value to the **endpoint** of the Azure Cosmos DB account you created earlier. The **credential** variable should be set to a new instance of the **DefaultAzureCredential** class:

   ```python
   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()
   ```

    > &#128221; For example, if your endpoint is: **https://dp420.documents.azure.com:443/**, the statement would be: **endpoint = "https://dp420.documents.azure.com:443/"**.

1. Add a new variable named **client** and initialize it as a new instance of the **CosmosClient** class using the **endpoint** and **credential** variables:

   ```python
   client = CosmosClient(endpoint, credential=credential)
   ```

1. Add a function named **main** to read and print account properties:

   ```python
   def main():
       account_info = client.get_database_account()
       print(f"Consistency Policy:	{account_info.ConsistencyPolicy}")
       print(f"Primary Region: {account_info.WritableLocations[0]['name']}")

   if __name__ == "__main__":
       main()
   ```

1. Your **script.py** file should now look like this:

   ```python
   from azure.cosmos import CosmosClient
   from azure.identity import DefaultAzureCredential

   endpoint = "<cosmos-endpoint>"
   credential = DefaultAzureCredential()

   client = CosmosClient(endpoint, credential=credential)

   def main():
       account_info = client.get_database_account()
       print(f"Consistency Policy:	{account_info.ConsistencyPolicy}")
       print(f"Primary Region: {account_info.WritableLocations[0]['name']}")

   if __name__ == "__main__":
       main()
    ```

1. **Save** the **script.py** file.

## Test the script

Now that the Python code to connect to the Azure Cosmos DB for NoSQL account is complete, you can test the script. This script will print the default consistency level and the name of the first writable region. When you created the account, you specified a location, and you should expect to see that same location value printed as the result of this script.

1. In **Visual Studio Code**, open the context menu for the **python/01-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Before running the script, you must log into Azure using the `az login` command. At the terminal window, run:

   ```bash
   az login
   ```

1. Run the script using the `python` command:

   ```bash
   python script.py
   ```

1. The script will now output the default consistency level and the first writable region. For example, if the default consistency level for the account is **Session**, and the first writable region was **East US**, the script would output:

   ```text
   Consistency Policy:   {'defaultConsistencyLevel': 'Session'}
   Primary Region: East US
   ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
[pypi.org/project/azure-identity]: https://pypi.org/project/azure-identity
