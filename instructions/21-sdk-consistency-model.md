---
lab:
    title: 'Configure consistency models in the portal and the Azure Cosmos DB SQL API SDK'
    module: 'Module 9 - Design and implement a replication strategy for Azure Cosmos DB SQL API'
---

# Configure consistency models in the portal and the Azure Cosmos DB SQL API SDK

The default consistency level for new Azure Cosmos DB SQL API accounts is session consistency. This default setting can be modified for all future requests. At an individual request level, you can go a step further and relax the consistency level for that specific request.

In this lab, we will configure the default consistency level for an Azure Cosmos DB SQL API account and then configure a consistency level for an individual operation using the SDK.

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
    | **Global Distribution** &vert; **Geo-Redundancy** | *Enable* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Replicate data globally** pane.

1. In the **Replicate data globally** pane, add two extra read regions to the account and then **Save** your changes.

1. Wait for the replication task to complete before continuing with this task.

    > &#128221; This operation can take approximately 5-10 minutes.and navigate to the **Default consistency** pane.

1. In the resource blade, navigate to the **Default consistency** pane.

1. In the **Default consistency** pane, select the **Strong** option and then **Save** your changes.

1. Wait for the change to the default consistency level to persist before continuing with this task.

1. In the resource blade, navigate to the **Data Explorer** pane.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Create new* &vert; *cosmicworks* |
    | **Share throughput across containers** | *Do not select* |
    | **Container id** | *products* |
    | **Partition key** | */categoryId* |
    | **Container throughput** | *Manual* &vert; *400* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

1. In the resource blade, navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Close your web browser window or tab.

## Connect to the Azure Cosmos DB SQL API account from the SDK

Using the credentials from the newly created account, you will connect with the SDK classes and create a new database and container instance. Then, you will use the Data Explorer to validate that the instances exist in the Azure portal.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **21-sdk-consistency-model** folder.

1. Open the context menu for the **21-sdk-consistency-model** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **21-sdk-consistency-model** folder.

1. Build the project using the [dotnet build][docs.microsoft.com/dotnet/core/tools/dotnet-build] command:

    ```
    dotnet build
    ```

    > &#128221; You may see a compiler warning that the **endpoint** and **key** variables are current unused. You can safely ignore this warning as you will use these variable in this task.

1. Close the integrated terminal.

1. Open the **product.cs** code file.

1. Observe the **Product** record and its corresponding properties. Specifically, this lab will use the **id**, **name**, and **categoryId** properties.

1. Back in the **Explorer** pane of **Visual Studio Code**, open the **script.cs** code file.

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

1. **Save** the **script.cs** code file.

## Configure consistency level for a point operation

The **ItemRequestOptions** class contains configuration properties on a per-request basis. Using this class, you will relax the consistency level from the current default of strong to eventual consistency.

1. Create two **string** variables named **id** and **categoryId** by generating a new **Guid** value and then storing the result as a string:

    ```
    string id = $"{Guid.NewGuid()}";
    string categoryId = $"{Guid.NewGuid()}";
    ```

1. Create a new variable named **item** of type **Product** passing in the **id** variable, a string value of **Reflective Handlebar**, and the **categoryId** variable as constructor parameters:

    ```
    Product item = new (id, "Reflective Handlebar", categoryId);
    ```

1. Create a new variable named **options** of type [ItemRequestOptions][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions] setting the [ConsistencyLevel][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions.consistencylevel] property to the [ConsistencyLevel.Eventual][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.consistencylevel] enum value:

    ```
    ItemRequestOptions options = new()
    { 
        ConsistencyLevel = ConsistencyLevel.Eventual 
    };
    ```

1. Create a variable of type **PartitionKey** named **partitionKey** passing in the **categoryId** variable as a constructor parameter:

    ```
    PartitionKey partitionKey = new (categoryId);
    ```

1. Asynchronously invoke the **CreateItemAsync\<\>** method of the **container** variable passing in the **item**, **partitionKey**, and **options** variables as parameters and storing the result in a variable named **response**:

    ```
    var response = await container.CreateItemAsync<Product>(item, partitionKey, requestOptions: options);
    ```

1. Invoke the static **Console.WriteLine** method to print the response's request charge (in request units):

    ```
    Console.WriteLine($"Charge (RU):\t{response.RequestCharge:0.00}");
    ```

1. Once you are done, your code file should now include:

    ```
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    using CosmosClient client = new CosmosClient(endpoint, key);
    
    Container container = client.GetContainer("cosmicworks", "products");
    
    string id = $"{Guid.NewGuid()}";
    string categoryId = $"{Guid.NewGuid()}";
    Product item = new (id, "Reflective Handlebar", categoryId);
    
    ItemRequestOptions options = new()
    { 
        ConsistencyLevel = ConsistencyLevel.Eventual 
    };
    
    PartitionKey partitionKey = new (categoryId);
    var response = await container.CreateItemAsync<Product>(item, partitionKey, requestOptions: options);

    Console.WriteLine($"Charge (RU):\t{response.RequestCharge:0.00}");
    ```

1. **Save** the **script.cs** code file.

1. In **Visual Studio Code**, open the context menu for the **21-sdk-consistency-model** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the **[dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run]** command:

    ```
    dotnet run
    ```

1. Observe the output from the terminal. The request charge (in RUs) should be printed to the console.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.consistencylevel]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.consistencylevel
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions.consistencylevel]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.itemrequestoptions.consistencylevel
[docs.microsoft.com/dotnet/core/tools/dotnet-build]: https://docs.microsoft.com/dotnet/core/tools/dotnet-build
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
