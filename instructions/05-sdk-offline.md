---
lab:
    title: 'Configure the Azure Cosmos DB SQL API SDK for offline development'
    module: 'Module 3 - Connect to Azure Cosmos DB SQL API with the SDK'
---

# Configure the Azure Cosmos DB SQL API SDK for offline development

The Azure Cosmos DB Emulator is a local tool that emulates the Azure Cosmos DB service for development and testing. The emulator supports the SQL API and can be used in place of the cloud service when developing code using the Azure SDK for .NET.

In this lab, you'll connect to the Azure Cosmos DB Emulator from the Azure SDK for .NET.

## Prepare your development environment

If you have not already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Getting Started documentation][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/microsoftlearning/dp-420-cosmos-db-dev`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, open the local folder you selected in **Visual Studio Code**.

## Start the Azure Cosmos DB Emulator

Your environment should already have the emulator pre-installed. If not, refer to the [installation instructions][docs.microsoft.com/azure/cosmos-db/local-emulator] to install the Azure Cosmos DB Emulator. Once the emulator has started, you can retrieve the connection string and use it to connect to the emulator using the Azure SDK for .NET or any other SDK of your choice.

1. Start the **Azure Cosmos DB Emulator**.

    > &#128221; You may be prompted to grant administrator access to start the emulator. In the lab environment, the **Admin** account has the same password as the **Student** account.

    > &#128161; The Azure Cosmos DB Emulator is pinned to both the Windows taskbar and Start Menu. ***If the Emulator does not start from the pinned icons, try opening it by double-clicking on the*** **C:\Program Files\Azure Cosmos DB Emulator\CosmosDB.Emulator.exe** ***file***. Note that the emulator takes 20-30 seconds to start.

1. Wait for the emulator to automatically open your default browser and navigate to the **localhost:8081/_explorer/index.html** landing page.

1. In the **Azure Cosmos DB Emulator** landing page, navigate to the **Quickstart** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **Primary Connection String** field. You will use this **connection string** value later in this exercise.

1. Navigate to the **Explorer** pane.

1. In the **Data Explorer**, observe that there are no nodes within the **SQL API** navigation tree.

1. Close your web browser window or tab.

## Connect to the emulator from the SDK

The **Microsoft.Azure.Cosmos** library has already been pre-installed in the .NET script you will use in this exercise. Further, some of the boilerplate code has already been written to save you time. You will need to update the boilerplate connection string value and write a couple of lines of code to complete the script.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **05-sdk-offline** folder.

1. Open the **script.cs** code file within the **05-sdk-offline** folder.

1. Update the existing variable named **connectionString** with its value set to the **connection string** of the Azure Cosmos DB Emulator.
  
    ```
    string connectionString = "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    ```

    > &#128221; The URI for the emulator is typically ***localhost:[port]*** using SSL with the default port set to **8081**.

    > &#128221; *C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==* is the default key for all installations of the emulator. This key can be changed using command line options.

1. Asynchronously invoke the [CreateDatabaseIfNotExistsAsync][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.createdatabaseifnotexistsasync] method of the **client** variable passing in the name of the new database (**cosmicworks**) you would like to create within the emulator and storing the result in a variable of type [Database][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database]:

    ```
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    ```

1. Use the built-in **Console.WriteLine** static method to print the [Id][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.id] property of the Database class with a header titled **New Database**:

    ```
    Console.WriteLine($"New Database:\tId: {database.Id}");
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;
    
    string connectionString = "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    
    CosmosClient client = new (connectionString);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    Console.WriteLine($"New Database:\tId: {database.Id}");
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **05-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **05-sdk-offline** folder.

1. Add the [Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Cosmos --version 3.22.1
    ```

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

## View the changes in the emulator

Now that you have created a new database in the Azure Cosmos DB emulator, you will use the online **Data Explorer** to observe the new SQL API database within the emulator.

1. Navigate to the emulator icon in the Windows system tray, open the context menu, and then select **Open Data Explorer...** to navigate to the **localhost:8081/_explorer/** landing page using your default browser.

1. In the **Azure Cosmos DB Emulator** landing page, navigate to the **Explorer** pane.

1. In the **Data Explorer**, observe the new **cosmicworks** database node within the **SQL API** navigation tree.

1. Close your web browser window or tab.

## Create and view a new container

Creating a new container is similar to the pattern used to create a new database. The code you learn here will be relevant whether or not you create resources in the cloud or in the emulator, you simply need to change the connection string. You will expand the script file further to create a new container along with the database.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **05-sdk-offline** folder.

1. Open the **script.cs** code file within the **05-sdk-offline** folder again.

1. Asynchronously invoke the [CreateContainerIfNotExistsAsync][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.createcontainerifnotexistsasync] method of the **database** variable passing in the name of the new container (**products**), the partition key path (**/categoryId**), and the throughput (**400**) you would like to create within the **cosmicworks** database and storing the result in a variable of type [Container][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container]:

    ```
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);
    ```

1. Use the built-in **Console.WriteLine** static method to print the [Id][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.id] property of the Container class with a header titled **New Container**:

    ```
    Console.WriteLine($"New Container:\tId: {container.Id}");
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;;
    
    string connectionString = "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    
    CosmosClient client = new (connectionString);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    Console.WriteLine($"New Database:\tId: {database.Id}");
    
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);
    Console.WriteLine($"New Container:\tId: {container.Id}");
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **05-sdk-offline** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

1. Navigate to the emulator icon in the Windows system tray, open the context menu, and then select **Open Data Explorer...** to navigate to the **localhost:8081/_explorer/** landing page using your default browser.

1. In the **Azure Cosmos DB Emulator** landing page, navigate to the **Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Close your web browser window or tab.

## Stop the Azure Cosmos DB Emulator

It is important to stop the emulator when you are done using it as it can use system resources in your environment. You will use the system tray icon to stop the emulator and all running instances.

1. Navigate to the emulator icon in the Windows system tray, open the context menu, and then select **Exit** to shut down the emulator.

    > &#128221; It may take a minute for all instances of the emulator to exit.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/azure/cosmos-db/local-emulator]: https://docs.microsoft.com/azure/cosmos-db/local-emulator
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.id]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.id
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.createdatabaseifnotexistsasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.createdatabaseifnotexistsasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.createcontainerifnotexistsasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.createcontainerifnotexistsasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.id]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.database.id
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
[nuget.org/packages/microsoft.azure.cosmos/3.22.1]: https://www.nuget.org/packages/Microsoft.Azure.Cosmos/3.22.1
