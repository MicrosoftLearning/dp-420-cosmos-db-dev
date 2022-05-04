---
lab:
    title: 'Implement and then use a UDF using the SDK'
    module: 'Module 13 - Create server-side programming constructs in Azure Cosmos DB SQL API'
---

# Implement and then use a UDF using the SDK

The .NET SDK for Azure Cosmos DB SQL API can be used to manage and invoke server-side programming constructs directly from a container. When preparing a new container, it may make sense to use the .NET SDK to publish UDFs directly to a container instead of performing the tasks manually using the Data Explorer.

In this lab, you'll create a new UDF using the .NET SDK and then use the Data Explorer to validate that the UDF is working correctly.

## Prepare your development environment

If you have not already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

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

## Seed the Azure Cosmos DB SQL API account with data

The [cosmicworks][nuget.org/packages/cosmicworks] command-line tool deploys sample data to any Azure Cosmos DB SQL API account. The tool is open-source and available through NuGet. You will install this tool to the Azure Cloud Shell and then use it to seed your database.

1. In **Visual Studio Code**, open the **Terminal** menu and then select **New Terminal** to open a new terminal instance.

1. Install the [cosmicworks][nuget.org/packages/cosmicworks] command-line tool for global use on your machine.

    ```
    dotnet tool install --global cosmicworks
    ```

    > &#128161; This command may take a couple of minutes to complete. This command will output the warning message (*Tool 'cosmicworks' is already installed') if you have already installed the latest version of this tool in the past.

1. Run cosmicworks to seed your Azure Cosmos DB account with the following command-line options:

    | **Option** | **Value** |
    | ---: | :--- |
    | **--endpoint** | *The endpoint value you copied earlier in this lab* |
    | **--key** | *The key value you coped earlier in this lab* |
    | **--datasets** | *product* |

    ```
    cosmicworks --endpoint <cosmos-endpoint> --key <cosmos-key> --datasets product
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/** and your key is: **fDR2ci9QgkdkvERTQ==**, then the command would be:
    > ``cosmicworks --endpoint https://dp420.documents.azure.com:443/ --key fDR2ci9QgkdkvERTQ== --datasets product``

1. Wait for the **cosmicworks** command to finish populating the account with a database, container, and items.

1. Close the integrated terminal.

## Create a user-defined function (UDF) using the .NET SDK

The [Container][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container] class in the .NET SDK includes a [Scripts][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.scripts] property that is used to perform CRUD operations against Stored Procedures, UDFs, and Triggers directly from the SDK. You will use this property to create a new UDF and then push that UDF to an Azure Cosmos DB SQL API container. The UDF that we will create using the SDK, will compute the price of the product with the tax, which will let us run SQL queries on the products using their price with the tax.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **33-create-use-udf-sdk** folder.

1. Open the **script.cs** code file.

1. Add a using block for the [Microsoft.Azure.Cosmos.Scripts][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts] namespace:

    ```
    using Microsoft.Azure.Cosmos.Scripts;
    ```

1. Update the existing variable named **endpoint** with its value set to the **endpoint** of the Azure Cosmos DB account you created earlier.
  
    ```
    string endpoint = "<cosmos-endpoint>";
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/**, then the C# statement would be: **string endpoint = "https&shy;://dp420.documents.azure.com:443/";**.

1. Update the existing variable named **key** with its value set to the **key** of the Azure Cosmos DB account you created earlier.

    ```
    string key = "<cosmos-key>";
    ```

    > &#128221; For example, if your key is: **fDR2ci9QgkdkvERTQ==**, then the C# statement would be: **string key = "fDR2ci9QgkdkvERTQ==";**.

1. Create a new variable of type [UserDefinedFunctionProperties][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties] named props using the default empty constructor:

    ```
    UserDefinedFunctionProperties props = new ();
    ```

1. Set the [Id][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.id] property of the **props** variable to a value of **tax**:

    ```
    props.Id = "tax";
    ```

1. Set the [Body][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.body] property of the **props** variable to a value of **props.Body = "function tax(i) { return i * 1.25; }";**:

    ```
    props.Body = "function tax(i) { return i * 1.25; }";
    ```

1. Asynchronously call the **container** variable's [Scripts.CreateUserDefinedFunctionAsync][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.scripts] method passing in the **props** variable as a parameter and saving the result in a variable named **udf** of type [UserDefinedFunctionResponse][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse]:

    ```
    UserDefinedFunctionResponse udf = await container.Scripts.CreateUserDefinedFunctionAsync(props);
    ```

1. Use the built-in **Console.WriteLine** static method to print the [Resource.Id][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse.resource] property of the UserDefinedFunctionResponse class with a header titled **Created UDF**:

    ```
    Console.WriteLine($"Created UDF [{udf.Resource?.Id}]");
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using Microsoft.Azure.Cosmos;
    using Microsoft.Azure.Cosmos.Scripts;

    string endpoint = "<cosmos-endpoint>";

    string key = "<cosmos-key>";

    CosmosClient client = new CosmosClient(endpoint, key);

    Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");

    Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId");

    UserDefinedFunctionProperties props = new ();
    props.Id = "tax";
    props.Body = "function tax(i) { return i * 1.25; }";
    
    UserDefinedFunctionResponse udf = await container.Scripts.CreateUserDefinedFunctionAsync(props);
    
    Console.WriteLine($"Created UDF [{udf.Resource?.Id}]");
    ```

1. **Save** the **script.cs** file.

1. In **Visual Studio Code**, open the context menu for the **33-create-use-udf-sdk** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```

1. The script will now output the name of the newly created UDF:

    ```
    Created UDF [tax]
    ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

## Test the UDF using the Data Explorer

Now that a new UDF has been created in the Azure Cosmos DB container, you will use the Data Explorer to validate that the UDF is working as expected.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, then observe the new **products** container node within the **SQL API** navigation tree.

1. Select the **products** container node within the **SQL API** navigation tree, and then select **New SQL Query**.

1. In the query tab, select **Execute Query** to view a standard query that selects all items without any filters.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents with two price values projected. The first value is the raw price value from the container, and the second value is the price value as calculated by the UDF:

    ```
    SELECT p.id, p.price, udf.tax(p.price) AS priceWithTax FROM products p
    ```

1. Select **Execute Query**.

1. Observe the documents and compare their **price** and **priceWithTax** fields.

    > &#128221; The **priceWithTax** field should have a value that is 25% larger than the **price** field.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.scripts]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.container.scripts
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.body]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.body
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.id]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionproperties.id
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse.resource]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.scripts.userdefinedfunctionresponse.resource
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
[nuget.org/packages/cosmicworks]: https://www.nuget.org/packages/cosmicworks/
