---
lab:
    title: 'Connect to Azure Cosmos DB SQL API with the SDK'
    module: 'Module 3 - Connect to Azure Cosmos DB SQL API with the SDK'
---

# Connect to Azure Cosmos DB SQL API with the SDK

The Azure SDK for .NET is a suite of libraries that provides a consistent developer interface to interact with many Azure services. The Azure SDK for .NET is built to the .NET Standard 2.0 specification ensuring that it can be used in .NET Framework (4.6.1 or above), .NET Core (2.1 or above), and .NET (5 or above) applications.

In this lab, you'll connect to an Azure Cosmos DB SQL API account using the Azure SDK for .NET.

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
    | **Limit the total amount of throughput that can be provisioned on this account** | *Unchecked* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Close your web browser window or tab.

## View the Microsoft.Azure.Cosmos library on NuGet

The NuGet website contains a searchable index of packages that are available to import into your .NET applications. To import prerelease packages such as **Microsoft.Azure.Cosmos**, you can use the NuGet website to get the appropriate versions and commands to import the package into your applications.

1. In a web browser, navigate to the NuGet website (``nuget.org``).

1. Review the description of NuGet, the package manager for .NET, and its capabilities.

1. Search for the **Microsoft.Azure.Cosmos** library on NuGet.org.

1. Select the **.NET CLI** tab to observe the command required to import the latest version of this library into a .NET project.

    > &#128161; No need to record this command. You will use a specific version of the library later in this exercise.

1. Close your web browser window or tab.

## Import the Microsoft.Azure.Cosmos library into a .NET project

The .NET CLI includes an [add package][docs.microsoft.com/dotnet/core/tools/dotnet-add-package] command to import packages from a pre-configured package feed. A .NET installation uses NuGet as its default package feed.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **04-sdk-connect** folder.

1. Open the context menu for the **04-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **04-sdk-connect** folder.

1. Add the [Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Cosmos --version 3.22.1
    ```

1. Close the integrated terminal.

## Use the Microsoft.Azure.Cosmos library

Once the Azure Cosmos DB library from the Azure SDK for .NET has been imported, you can immediately use its classes within the [Microsoft.Azure.Cosmos][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos] namespace to connect to an Azure Cosmos DB SQL API account. The [CosmosClient][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient] class is the core class that is used to make the initial connection to an Azure Cosmos DB SQL API account.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **04-sdk-connect** folder.

1. Open the empty **script.cs** code file.

1. Add using blocks for the built-in **System** and **System.Linq** namespaces:

    ```
    using System;
    using System.Linq;
    ```

1. Add a using block for the [Microsoft.Azure.Cosmos][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos] namespace:

    ```
    using Microsoft.Azure.Cosmos;
    ```

1. Add a **string** variable named **endpoint** with its value set to the **endpoint** of the Azure Cosmos DB account you created earlier.
  
    ```
    string endpoint = "<cosmos-endpoint>";
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/**, then the C# statement would be: **string endpoint = "https&shy;://dp420.documents.azure.com:443/";**.

1. Add a **string** variable named **key** with its value set to the **key** of the Azure Cosmos DB account you created earlier.

    ```
    string key = "<cosmos-key>";
    ```

    > &#128221; For example, if your key is: **fDR2ci9QgkdkvERTQ==**, then the C# statement would be: **string key = "fDR2ci9QgkdkvERTQ==";**.

1. Add a new variable named **client** of type [CosmosClient][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient] using the **endpoint** and **key** variables in the constructor:
  
    ```
    CosmosClient client = new (endpoint, key);
    ```

1. Add a new variable named **account** of type [AccountProperties][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties] using the asynchronous result of invoking the [ReadAccountAsync][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.readaccountasync] method of the **client** variable:

    ```
    AccountProperties account = await client.ReadAccountAsync();
    ```

1. Use the built-in **Console.WriteLine** static method to print the [Id][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.id] property of the AccountProperties class with a header titled **Account Name**:

    ```
    Console.WriteLine($"Account Name:\t{account.Id}");
    ```

1. Use the built-in **Console.WriteLine** static method to query the [WritableRegions][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.writableregions] property of the AccountProperties class and then print the [Name][docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountregion.name] property of the first result with a header titled **Primary Region**:

    ```
    Console.WriteLine($"Primary Region:\t{account.WritableRegions.FirstOrDefault()?.Name}");
    ```

1. Once you are done, your code file should now include:
  
    ```
    using System;
    using System.Linq;
    
    using Microsoft.Azure.Cosmos;

    string endpoint = "<cosmos-endpoint>";
    string key = "<cosmos-key>";

    CosmosClient client = new (endpoint, key);

    AccountProperties account = await client.ReadAccountAsync();

    Console.WriteLine($"Account Name:\t{account.Id}");
    Console.WriteLine($"Primary Region:\t{account.WritableRegions.FirstOrDefault()?.Name}");
    ```

1. **Save** the **script.cs** code file.

## Test the script

Now that the .NET code to connect to the Azure Cosmos DB SQL API account is complete, you can test the script. This script will print the name of the account, and the name of the first writable region. When you created the account, you specified a location and you should expect to see that same location value printed as the result of this script.

1. In **Visual Studio Code**, open the context menu for the **04-sdk-connect** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```

1. The script will now output the name of the account, and the first writable region. For example, if you named the account **dp420**, and the first writable region was **West US 2**, the script would output:

    ```
    Account Name:   dp420
    Primary Region: West US 2
    ```

1. Close the integrated terminal.

1. Close **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.id]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.id
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.writableregions]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountproperties.writableregions
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountregion.name]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.accountregion.name
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient
[docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.readaccountasync]: https://docs.microsoft.com/dotnet/api/microsoft.azure.cosmos.cosmosclient.readaccountasync
[docs.microsoft.com/dotnet/core/tools/dotnet-add-package]: https://docs.microsoft.com/dotnet/core/tools/dotnet-add-package
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
[nuget.org/packages/microsoft.azure.cosmos/3.22.1]: https://www.nuget.org/packages/Microsoft.Azure.Cosmos/3.22.1
