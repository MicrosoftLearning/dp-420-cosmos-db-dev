---
lab:
    title: '02 - Configure the Azure Cosmos DB JavaScript SDK for Offline Development'
    module: 'Configure the Azure Cosmos DB for NoSQL SDK'
---

# Configure the Azure Cosmos DB Python SDK for Offline Development

The Azure Cosmos DB Emulator is a local tool that emulates the Azure Cosmos DB service for development and testing. The emulator supports the NoSQL API and can be used in place of the cloud service when developing code using the Azure SDK for Python.

In this lab, you'll connect to the Azure Cosmos DB Emulator from the Azure SDK for Python.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Start the Azure Cosmos DB Emulator

If you are using a hosted lab environment, it should already have the emulator installed. If not, refer to the [installation instructions](https://docs.microsoft.com/azure/cosmos-db/local-emulator) to install the Azure Cosmos DB Emulator. Once the emulator has started, you can retrieve the connection string and use it to connect to the emulator using the Azure SDK for Python.

> &#128161; You may optionally install the [new Linux-based Azure Cosmos DB Emulator (in preview)](https://learn.microsoft.com/azure/cosmos-db/emulator-linux), which is available as a Docker container. It supports running on a wide variety of processors and operating systems.

1. Start the **Azure Cosmos DB Emulator**.

    > 💡 If you are using Windows, the Azure Cosmos DB Emulator is pinned to both the Windows taskbar and Start Menu. If it does not start from the pinned icons, try opening it by double-clicking on the **C:\Program Files\Azure Cosmos DB Emulator\CosmosDB.Emulator.exe** file.

1. Wait for the emulator to open your default browser and navigate to the **https://localhost:8081/_explorer/index.html** landing page.

1. In the **Quickstart** pane, note the **Primary Connection String**. You will use this connection string later.

> &#128221; Sometimes the landing page does not successfully load, even though the emulator is running. If this happens, you can use the well-known connection string to connect to the emulator. The well-known connection string is: `AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==`

## Install the azure-cosmos library

The **azure-cosmos** library is available on **PyPI** for easy installation into your Python projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/02-sdk-offline** folder.

1. Open the context menu for the **python/02-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **python/02-sdk-offline** folder.

1. Create and activate a virtual environment to manage dependencies:

   ```bash
   python -m venv venv
   source venv/bin/activate   # On Windows, use `venv\Scripts\activate`
   ```

1. Install the [azure-cosmos][pypi.org/project/azure-cosmos] package using the following command:

   ```bash
   pip install azure-cosmos
   ```

## Connect to the Emulator from the Python SDK

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **python/02-sdk-offline** folder.

1. Open the blank Python file named **script.py**.

1. Add the following code to connect to the emulator, create a database, and print its ID:

   ```python
   from azure.cosmos import CosmosClient, PartitionKey
   
   # Connection string for the Azure Cosmos DB Emulator
   connection_string = "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
    
   # Initialize the Cosmos client
   client = CosmosClient.from_connection_string(connection_string)
    
   # Create a database
   database_name = "cosmicworks"
   database = client.create_database_if_not_exists(id=database_name)
    
   # Print the database ID
   print(f"New Database: Id: {database.id}")
   ```

1. **Save** the **script.py** file.

## Run the script

1. Use the same terminal window in **Visual Studio Code** that you used to set up the Python environment for this lab. If you close it, open the context menu for the **python/02-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Run the script using the `python` command:

   ```bash
   python script.py
   ```

1. The script creates a database named `cosmicworks` in the emulator. You should see output similar to the following:

   ```text
   New Database: Id: cosmicworks
   ```

## Create and View a New Container

You can extend the script to create a container within the database.

### Updated Code

1. Modify the `script.py` file to add the following code at the bottom of the file for creating a container:

   ```python
   # Create a container
   container_name = "products"
   partition_key_path = "/categoryId"
   throughput = 400
    
   container = database.create_container_if_not_exists(
       id=container_name,
       partition_key=PartitionKey(path=partition_key_path),
       offer_throughput=throughput
   )
    
   # Print the container ID
   print(f"New Container: Id: {container.id}")
   ```

### Run the Updated Script

1. Run the updated script using the following command:

   ```bash
   python script.py
   ```

1. The script creates a container named `products` in the emulator. You should see output similar to the following:

   ```text
   New Container: Id: products
   ```

### Verify the Results

1. Switch to the browser where the emulator's Data Explorer is open.

1. Refresh the **NoSQL API** to observe the new **cosmicworks** database and **products** container.

## Stop the Azure Cosmos DB Emulator

It is important to stop the emulator when you are done using it to free up system resources. Follow the steps below based on your operating system:

### On macOS or Linux:

If you started the emulator in a terminal window, follow these steps:

1. Locate the terminal window where the emulator is running.

1. Press `Ctrl + C` to terminate the emulator process.

Alternatively, if you need to stop the emulator process manually:

1. Open a new terminal window.

1. Use the following command to find the emulator process:

   ```bash
   ps aux | grep CosmosDB.Emulator
   ```

Identify the **PID** (Process ID) of the emulator process in the output. Use the kill command to terminate the emulator process:

```bash
kill <PID>
```

### On Windows:

1. Locate the Azure Cosmos DB Emulator icon in the Windows System Tray (near the clock on the taskbar).

1. Right-click on the emulator icon to open the context menu.

1. Select **Exit** to shut down the emulator.

> 💡 It may take a minute for all instances of the emulator to exit.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[pypi.org/project/azure-cosmos]: https://pypi.org/project/azure-cosmos
