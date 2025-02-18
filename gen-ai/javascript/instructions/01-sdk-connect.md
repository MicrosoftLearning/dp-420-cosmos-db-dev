---
title: '01 - Connect to Azure Cosmos DB for NoSQL with the SDK'
lab:
    title: '01 - Connect to Azure Cosmos DB for NoSQL with the SDK'
    module: 'Use the Azure Cosmos DB for NoSQL SDK'
layout: default
nav_order: 4
parent: 'JavaScript SDK labs'
---

# Connect to Azure Cosmos DB for NoSQL with the SDK

The Azure SDK for JavaScript (Node.js & Browser) is a suite of client libraries that provides a consistent developer interface to interact with many Azure services. Client libraries are packages that you would use to consume these resources and interact with them.

In this lab, you'll connect to an Azure Cosmos DB for NoSQL account using the Azure SDK for JavaScript.

## Prepare your development environment

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** and set up your local environment, view the [Setup local lab environment](00-setup-lab-environment.md) instructions to do so.

## Create an Azure Cosmos DB for NoSQL account

If you already created an Azure Cosmos DB for NoSQL account for the **Build copilots with Azure Cosmos DB** labs on this site, you can use it for this lab and skip ahead to the [next section](#import-the-azurecosmos-library). Otherwise, view the [Setup Azure Cosmos DB](../../common/instructions/00-setup-cosmos-db.md) instructions to create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role.

## Import the @azure/cosmos library

The **@azure/cosmos** library is available on **npm** for easy installation into your JavaScript projects.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/01-sdk-connect** folder.

1. Open the context menu for the **javascript/01-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **javascript/01-sdk-connect** folder.

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

## Use the @azure/cosmos library

Once the Azure Cosmos DB library from the Azure SDK for JavaScript has been imported, you can immediately use its classes to connect to an Azure Cosmos DB for NoSQL account. The **CosmosClient** class is the core class used to make the initial connection to an Azure Cosmos DB for NoSQL account.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **javascript/01-sdk-connect** folder.

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

1. Add an `async` function named **main** to read and print account properties:

    ```javascript
    async function main() {
        const { resource: account } = await client.getDatabaseAccount();
        console.log(`Consistency Policy: ${account.consistencyPolicy}`);
        console.log(`Primary Region: ${account.writableLocations[0].name}`);
    }
    ```

1. Invoke the **main** function:

    ```javascript
    main().catch((error) => console.error(error));
    ```

1. Your **script.js** file should now look like this:

    ```javascript
    const { CosmosClient } = require("@azure/cosmos");
    const { DefaultAzureCredential  } = require("@azure/identity");
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0

    const endpoint = "<cosmos-endpoint>";
    const credential = new DefaultAzureCredential();

    const client = new CosmosClient({ endpoint, aadCredentials: credential });

    async function main() {
        const { resource: account } = await client.getDatabaseAccount();
        console.log(`Consistency Policy: ${account.consistencyPolicy}`);
        console.log(`Primary Region: ${account.writableLocations[0].name}`);
    }

    main().catch((error) => console.error(error));
    ```

1. **Save** the **script.js** file.

## Test the script

Now that the JavaScript code to connect to the Azure Cosmos DB for NoSQL account is complete, you can test the script. This script will print the default consistency level and the name of the first writable region. When you created the account, you specified a location, and you should expect to see that same location value printed as the result of this script.

1. In **Visual Studio Code**, open the context menu for the **javascript/01-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Before running the script, you must log into Azure using the `az login` command. At the terminal window, run:

    ```bash
    az login
    ```

1. Run the script using the `node` command:

    ```bash
    node script.js
    ```

1. The script will now output the default consistency level of the account and the first writable region. For example, if default consistency level for the account is **Session**, and the first writable region was **East US**, the script would output:

    ```text
    Consistency Policy: Session
    Primary Region: East US
    ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[npmjs.com/package/@azure/cosmos]: https://www.npmjs.com/package/@azure/cosmos
[npmjs.com/package/@azure/identity]: https://www.npmjs.com/package/@azure/identity
