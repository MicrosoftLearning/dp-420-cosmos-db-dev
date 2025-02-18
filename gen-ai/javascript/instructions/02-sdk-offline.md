---
title: '02 - Configure the Azure Cosmos DB JavaScript SDK for Offline Development'
lab:
    title: '02 - Configure the Azure Cosmos DB JavaScript SDK for Offline Development'
    module: 'Configure the Azure Cosmos DB for NoSQL SDK'
layout: default
nav_order: 5
parent: 'JavaScript SDK labs'
---

# Configure the Azure Cosmos DB JavaScript SDK for Offline Development

The Azure Cosmos DB Emulator is a local tool that emulates the Azure Cosmos DB service for development and testing. The emulator supports the NoSQL API and can be used in place of the cloud service when developing code using the Azure SDK for JavaScript.

In this lab, you'll connect to the Azure Cosmos DB Emulator from the Azure SDK for JavaScript.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Start the Azure Cosmos DB Emulator

If you are using a hosted lab environment, it should already have the emulator installed. If not, refer to the [installation instructions](https://docs.microsoft.com/azure/cosmos-db/local-emulator) to install the Azure Cosmos DB Emulator. Once the emulator has started, you can retrieve the connection string and use it to connect to the emulator using the Azure SDK for JavaScript.

> &#128161; You may optionally install the [new Linux-based Azure Cosmos DB Emulator (in preview)](https://learn.microsoft.com/azure/cosmos-db/emulator-linux), which is available as a Docker container. It supports running on a wide variety of processors and operating systems.

1. Start the **Azure Cosmos DB Emulator**.

    > 💡 If you are using Windows, the Azure Cosmos DB Emulator is pinned to both the Windows taskbar and Start Menu. If it does not start from the pinned icons, try opening it by double-clicking on the **C:\Program Files\Azure Cosmos DB Emulator\CosmosDB.Emulator.exe** file.

1. Wait for the emulator to open your default browser and navigate to the **https://localhost:8081/_explorer/index.html** landing page.

1. In the **Quickstart** pane, note the **Primary Connection String**. You will use this connection string later.

> &#128221; Sometimes the landing page does not successfully load, even though the emulator is running. If this happens, you can use the well-known connection string to connect to the emulator. The well-known connection string is: `AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==`

## Import the @azure/cosmos library

The **@azure/cosmos** library is available on **npm** for easy installation into your JavaScript projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/02-sdk-offline** folder.

1. Open the context menu for the **javascript/02-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > 💡 This command will open the terminal with the starting directory already set to the **javascript/02-sdk-offline** folder.

1. Initialize a new Node.js project:

    ```bash
    npm init -y
    ```

1. Install the [@azure/cosmos][npmjs.com/package/@azure/cosmos] package using the following command:

    ```bash
    npm install @azure/cosmos
    ```

## Connect to the Emulator from the JavaScript SDK

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/02-sdk-offline** folder.

1. Open the blank JavaScript file named **script.js**.

1. Add the following code to connect to the emulator, create a database, and print its ID:

    ```javascript
    const { CosmosClient } = require("@azure/cosmos");
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0
    
    // Connection string for the Azure Cosmos DB Emulator
    const endpoint = "https://127.0.0.1:8081/";
    const key = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    
    // Initialize the Cosmos client
    const client = new CosmosClient({ endpoint, key });
    
    async function main() {
        // Create a database
        const databaseName = "cosmicworks";
        const { database } = await client.databases.createIfNotExists({ id: databaseName });
    
        // Print the database ID
        console.log(`New Database: Id: ${database.id}`);
    }
    
    main().catch((error) => console.error(error));
    ```

1. **Save** the **script.js** file.

## Run the script

1. Use the same terminal window in **Visual Studio Code** that you used to install the library for this lab. If you close it, open the context menu for the **javascript/02-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Run the script using the `node` command:

    ```bash
    node script.js
    ```

1. The script creates a database named `cosmicworks` in the emulator. You should see output similar to the following:

    ```text
    New Database: Id: cosmicworks
    ```

## Create and View a New Container

You can extend the script to create a container within the database.

### Updated Code

1. Modify the `script.js` file to **replace** the following line at the bottom of the file (`main().catch((error) => console.error(error));`) to create a container:

```javascript
async function createContainer() {
    const containerName = "products";
    const partitionKeyPath = "/categoryId";
    const throughput = 400;

    const { container } = await client.database("cosmicworks").containers.createIfNotExists({
        id: containerName,
        partitionKey: { paths: [partitionKeyPath] },
        throughput: throughput
    });

    // Print the container ID
    console.log(`New Container: Id: ${container.id}`);
}

main()
    .then(createContainer)
    .catch((error) => console.error(error));
```

The `script.js` file should now look like this:

```javascript
const { CosmosClient } = require("@azure/cosmos");
process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0

// Connection string for the Azure Cosmos DB Emulator
const endpoint = "https://127.0.0.1:8081/";
const key = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

// Initialize the Cosmos client
const client = new CosmosClient({ endpoint, key });

async function main() {
    // Create a database
    const databaseName = "cosmicworks";
    const { database } = await client.databases.createIfNotExists({ id: databaseName });

    // Print the database ID
    console.log(`New Database: Id: ${database.id}`);
}

async function createContainer() {
    const containerName = "products";
    const partitionKeyPath = "/categoryId";
    const throughput = 400;

    const { container } = await client.database("cosmicworks").containers.createIfNotExists({
        id: containerName,
        partitionKey: { paths: [partitionKeyPath] },
        throughput: throughput
    });

    // Print the container ID
    console.log(`New Container: Id: ${container.id}`);
}

main()
    .then(createContainer)
    .catch((error) => console.error(error));
```

### Run the Updated Script

1. Run the updated script using the following command:

    ```bash
    node script.js
    ```

1. The script creates a container named `products` in the emulator. You should see output similar to the following:

    ```text
    New Database: Id: cosmicworks
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
[npmjs.com/package/@azure/cosmos]: https://www.npmjs.com/package/@azure/cosmos
