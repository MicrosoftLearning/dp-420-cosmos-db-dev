---
lab:
    title: 'Create and update documents with the Azure Cosmos DB SQL API SDK'
    module: 'Module 4 - Implement Azure Cosmos DB SQL API point operations'
---

# Create and update documents with the Azure Cosmos DB SQL API SDK

The [Microsoft.Azure.Cosmos.Container][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container] class includes a set of member methods to create, retrieve, update, and delete items within an Azure Cosmos DB SQL API container. Together, these methods perform some of the most common “CRUD” operations across various items within SQL API containers.

In this lab, you’ll use the SDK to perform everyday CRUD operations on an item within an Azure Cosmos DB SQL API container.

## Prepare your development environment

If you have not already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Getting Started documentation][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/microsoftlearning/dp-420-cosmos-db-dev`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, open the local folder you selected in **Visual Studio Code**.

## Create an Azure Cosmos DB SQL API account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you will select which of the APIs you want the account to support (for example, **Mongo API** or **SQL API**). Once the Azure Cosmos DB SQL API account is done provisioning, you can retrieve the endpoint and key and use them to connect to the Azure Cosmos DB SQL API account using the Azure SDK for .NET or any other SDK of your choice.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB SQL API** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Close your web browser window or tab.

## Connect to the Azure Cosmos DB SQL API account from the SDK

Using the credentials from the newly created account, you will connect with the SDK classes and create a new database and container instance. Then, you will use the Data Explorer to validate that the instances exist in the Azure portal.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **06-sdk-crud** folder.

1. Open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **06-sdk-crud** folder.

1. Add the [Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Cosmos --version 3.22.1
    ```

1. Build the project using the [dotnet build][docs.microsoft.com/dotnet/core/tools/dotnet-build] command:

    ```
    dotnet build
    ```

1. Close the integrated terminal.

1. Open the **script.cs** code file within the **06-sdk-crud** folder.

    > &#128221; The **[Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1]** library has already been pre-imported from NuGet.

1. Locate the **string** variable named **endpoint**. Set its value to the **endpoint** of the Azure Cosmos DB account you created earlier.
  
    ```
    string endpoint = "<cosmos-endpoint>";
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/**, then the C# statement would be: **string endpoint = "https&shy;://dp420.documents.azure.com:443/";**.

1. Locate the **string** variable named **key**. Set its value to the **key** of the Azure Cosmos DB account you created earlier.

    ```
    string key = "<cosmos-key>";
    ```

    > &#128221; For example, if your key is: **fDR2ci9QgkdkvERTQ==**, then the C# statement would be: **string key = "fDR2ci9QgkdkvERTQ==";**.

1. Asynchronously invoke the CreateDatabaseIfNotExistsAsync method of the **client** variable passing in the name of the new database (**cosmicworks**) you would like to create, and storing the result in a variable of type **Database**:

    ```
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    ```

1. Asynchronously invoke the **CreateContainerIfNotExistsAsync** method of the **database** variable passing in the name of the new container (**products**), the partition key path (**/categoryId**), and the throughput (**400**) you would like to create within the **cosmicworks** database and storing the result in a variable of type **Container**:
  
    ```
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);    
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    CosmosClient client = new CosmosClient(endpoint, key);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Close your web browser window or tab.

## Perform create and read point operations on items with the SDK

You will now use the set of asynchronous methods in the Microsoft.Azure.Cosmos.Container class to perform common operations on items within a SQL API container. These operations are all done using the task asynchronous programming model in C#.

1. Return to **Visual Studio Code**. Open the **product.cs** code file within the **06-sdk-crud** folder.

    > &#128221; Do not close the editor for the **script.cs** file.

1. Observe the **Product** class within this code file. This class represents a product item that will be stored and manipulated within this container.

1. Return to the editor tab for the **script.cs** code file.

1. Create a new object of type **Product** named **saddle** with the following properties:

    | Property | Value |
    | ---: | :--- |
    | **id** | *706cd7c6-db8b-41f9-aea2-0e0c7e8eb009* |
    | **categoryId** | *9603ca6c-9e28-4a02-9194-51cdb7fea816* |
    | **name** | *Road Saddle* |
    | **price** | *45.99d* |
    | **tags** | *{ tan, new, crisp }* |

    ```
    Product saddle = new()
    {
        id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
        categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816",
        name = "Road Saddle",
        price = 45.99d,
        tags = new string[]
        {
            "tan",
            "new",
            "crisp"
        }
    };
    ```

1. Asynchronously invoke the generic [CreateItemAsync<>][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.createitemasync] method of the **container** variable passing in the **saddle** variable as the method parameter and using **Product** as the generic type:

    ```
    await container.CreateItemAsync<Product>(saddle);
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    CosmosClient client = new CosmosClient(endpoint, key);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);

    Product saddle = new()
    {
        id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
        categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816",
        name = "Road Saddle",
        price = 45.99d,
        tags = new string[]
        {
            "tan",
            "new",
            "crisp"
        }
    };

    await container.CreateItemAsync<Product>(saddle);
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the **[dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run]** command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

1. Return to the editor tab for the **script.cs** code file.

1. Delete the following lines of code:

    ```
    Product saddle = new()
    {
        id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009",
        categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816",
        name = "Road Saddle",
        price = 45.99d,
        tags = new string[]
        {
            "tan",
            "new",
            "crisp"
        }
    };

    await container.CreateItemAsync<Product>(saddle);
    ```

1. Create a string variable named **id** with a value of **706cd7c6-db8b-41f9-aea2-0e0c7e8eb009**:

    ```
    string id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009";
    ```

1. Create a string variable named **categoryId** with a value of **9603ca6c-9e28-4a02-9194-51cdb7fea816**:

    ```
    string categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816";
    ```

1. Create a variable of type [PartitionKey][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.partitionkey] named **partitionKey** passing in the **categoryId** variable as a constructor parameter:

    ```
    PartitionKey partitionKey = new (categoryId);
    ```

1. Asynchronously invoke the generic [ReadItemAsync<>][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.readitemasync] method of the **container** variable passing in the **id** and **partitionkey** variables as method parameters, using **Product** as the generic type, and storing the result in a variable named **saddle** of type **Product**:

    ```
    Product saddle = await container.ReadItemAsync<Product>(id, partitionKey);
    ```

1. Invoke the static **Console.WriteLine** method to print the saddle object using a formatted output string:

    ```
    Console.WriteLine($"[{saddle.id}]\t{saddle.name} ({saddle.price:C})");
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    CosmosClient client = new CosmosClient(endpoint, key);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);

    string id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009";

    string categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816";
    PartitionKey partitionKey = new (categoryId);

    Product saddle = await container.ReadItemAsync<Product>(id, partitionKey);

    Console.WriteLine($"[{saddle.id}]\t{saddle.name} ({saddle.price:C})");
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the **[dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run]** command:

    ```
    dotnet run
    ```

1. Observe the output from the terminal. Specifically, observe the formatted output text with the id, name, and price from the item.

1. Close the integrated terminal.

## Perform update and delete point operations with the SDK

While learning the SDK, it's not uncommon to use an online Azure Cosmos DB SDK account or the emulator to update an item and  oscillate back-and-forth between the Data Explorer and your IDE of choice as you perform an operation and check to see if your change has been applied. Here, you will do just that as you update and delete an item using the SDK.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **SQL API** navigation tree.

1. Select the **Items** node. Select the only item within the container and then observe the values of the **name** and **price** properties of the item.

    | **Property** | **Value** |
    | ---: | :--- |
    | **Name** | *Road Saddle* |
    | **Price** | *$45.99* |

    > &#128221; At this point in time, these values should not have been changed since you have created the item. You will change these values in this exercise.

1. Close your web browser window or tab.

1. Return to **Visual Studio Code**. Return to the editor tab for the **script.cs** code file.

1. Delete the following lines of code:

    ```
    Console.WriteLine($"[{saddle.id}]\t{saddle.name} ({saddle.price:C})");
    ```

1. Change the **saddle** variable by setting the value of the price property to **32.55**:

    ```
    saddle.price = 32.55d;
    ```

1. Modify the **saddle** variable again by setting the value of the **name** property to **Road LL Saddle**:

    ```
    saddle.name = "Road LL Saddle";
    ```

1. Asynchronously invoke the generic [UpsertItemAsync<>][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.upsertitemasync] method of the **container** variable passing in the **saddle** variable as the method parameter and using **Product** as the generic type:

    ```
    await container.UpsertItemAsync<Product>(saddle);
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    CosmosClient client = new CosmosClient(endpoint, key);
    
    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
    
    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);

    string id = "706cd7c6-db8b-41f9-aea2-0e0c7e8eb009";

    string categoryId = "9603ca6c-9e28-4a02-9194-51cdb7fea816";
    PartitionKey partitionKey = new (categoryId);

    Product saddle = await container.ReadItemAsync<Product>(id, partitionKey);

    saddle.price = 32.55d;
    saddle.name = "Road LL Saddle";
    
    await container.UpsertItemAsync<Product>(saddle);
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the **[dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run]** command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **SQL API** navigation tree.

1. Select the **Items** node. Select the only item within the container and then observe the values of the **name** and **price** properties of the item.

    | **Property** | **Value** |
    | ---: | :--- |
    | **Name** | *Road LL Saddle* |
    | **Price** | *$32.55* |

    > &#128221; At this point in time, these values should  have been changed since you have observed the item.

1. Close your web browser window or tab.

1. Return to **Visual Studio Code**. Return to the editor tab for the **script.cs** code file.

1. Delete the following lines of code:

    ```
    Product saddle = await container.ReadItemAsync<Product>(id, partitionKey);

    saddle.price = 32.55d;
    saddle.name = "Road LL Saddle";
    
    await container.UpsertItemAsync<Product>(saddle);
    ```

1. Asynchronously invoke the generic [DeleteItemAsync<>][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.deleteitemasync] method of the **container** variable passing in the **id** and **partitionkey** variables as method parameters and using **Product** as the generic type:

    ```
    await container.DeleteItemAsync<Product>(id, partitionKey);
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **06-sdk-crud** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the **[dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run]** command:

    ```
    dotnet run
    ```

1. Close the integrated terminal.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then expand the new **products** container node within the **SQL API** navigation tree.

1. Select the **Items** node. Observe that the items list is now empty.

1. Close your web browser window or tab.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.createitemasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.createitemasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.deleteitemasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.deleteitemasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.readitemasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.readitemasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.upsertitemasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.upsertitemasync
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.partitionkey]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.partitionkey
[docs.microsoft.com/dotnet/core/tools/dotnet-build]: https://docs.microsoft.com/dotnet/core/tools/dotnet-build
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
[nuget.org/packages/microsoft.azure.cosmos/3.22.1]: https://www.nuget.org/packages/Microsoft.Azure.Cosmos/3.22.1
