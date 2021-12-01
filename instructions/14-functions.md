---
lab:
    title: 'Process Azure Cosmos DB SQL API data using Azure Functions'
    module: 'Module 7 - Integrate Azure Cosmos DB SQL API with Azure services'
---

# Process Azure Cosmos DB SQL API data using Azure Functions

The Azure Cosmos DB trigger for Azure Functions is implemented using a change feed processor. You can create functions that respond to create and update operations in your Azure Cosmos DB SQL API container with this knowledge. If you have implemented a change feed processor manually, the setup for Azure Functions is similar.

In this lab, you will

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
    | **Capacity mode** | *Serverless* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You will use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You will use this **key** value later in this exercise.

1. Select **Data Explorer** from the resource menu.

1. In the **Data Explorer** pane, expand **New Container** and then select **New Database**.

1. In the **New Database** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *cosmicworks* |

1. Back in the **Data Explorer** pane, observe the **cosmicworks** database node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *cosmicworks* |
    | **Container id** | *products* |
    | **Partition key** | */categoryId* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container** again.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *cosmicworks* |
    | **Container id** | *productslease* |
    | **Partition key** | */id* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **productslease** container node within the hierarchy.

1. Return to the **Home** of the Azure portal.

## Create an Azure Function app and Azure Cosmos DB-triggered function

Before you can begin writing code, you will need to create the Azure Functions resource and its dependent resources (Application Insights, Storage) using the creation wizard.

1. Select **+ Create a resource**, search for *Functions*, and then create a new **Function App** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Name** | *Enter a globally unique name* |
    | **Publish** | *Code* |
    | **Runtime stack** | *.NET* |
    | **Version** | *6* |
    | **Region** | *Choose any available region* |
    | **Storage account** | *Create a new storage account* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Functions** account resource and navigate to the **Functions** pane.

1. In the **Functions** pane, select **+ Create**.

1. In the **Create function** popup, create a new function with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Development environment** | *Develop in portal* |
    | **Select a template** | *Azure Cosmos DB trigger* |
    | **New Function** | *ItemsListener* |
    | **Cosmos DB account connection** | *Select New* &vert; *Select Azure Cosmos DB Account* &vert; *Select the Azure Cosmos DB account you created earlier* |
    | **Database name** | *cosmicworks* |
    | **Collection name** | *products* |
    | **Collection name for leases** | *productslease* |
    | **Create lease collection if it does not exist** | *No* |

## Implement function code in .NET

The function you created earlier is a C# script that is edited in-portal. You will now use the portal to write a short function to output the unique identifier of any item inserted or updated in the container.

1. In the **ItemsListener** &vert; **Function** pane, navigate to the **Code + Test** pane.

1. In the editor for the **run.csx** script, delete the contents of the editor area.

1. In the editor area, reference the **Microsoft.Azure.DocumentDB.Core** library:

    ```
    #r "Microsoft.Azure.DocumentDB.Core"
    ```

1. Add using blocks for the **System**, **System.Collections.Generic**, and [Microsoft.Azure.Documents][docs.microsoft.com/dotnet/api/microsoft.azure.documents] namespaces:

    ```
    using System;
    using System.Collections.Generic;
    using Microsoft.Azure.Documents;
    ```

1. Create a new static method named **Run** that has two parameters:

    1. A parameter named **input** of type **IReadOnlyList\<\>** with a generic type of [Document][docs.microsoft.com/dotnet/api/microsoft.azure.documents.document].

    1. A parameter named **log** of type **ILogger**.

    ```
    public static void Run(IReadOnlyList<Document> input, ILogger log)
    {
    }
    ```

1. Within the **Run** method, invoke the **LogInformation** method of the **log** variable passing in a string that calculates the count of items in the current batch:

    ```
    log.LogInformation($"# Modified Items:\t{input?.Count ?? 0}"); 
    ```

1. Still within the **Run** method, create a foreach loop that iterates over the **input** variable using the variable **item** to represent an instance of type **Document**:

    ```
    foreach(Document item in input)
    {
    }
    ```

1. Within the foreach loop of the **Run** method, invoke the **LogInformation** method of the **log** variable passing in a string that prints the [Id][docs.microsoft.com/dotnet/api/microsoft.azure.documents.resource.id] property of the **item** variable:

    ```
    log.LogInformation($"Detected Operation:\t{item.Id}");
    ```

1. Once you are done, your code file should now include:
  
    ```
    #r "Microsoft.Azure.DocumentDB.Core"
    
    using System;
    using System.Collections.Generic;
    using Microsoft.Azure.Documents;
    
    public static void Run(IReadOnlyList<Document> input, ILogger log)
    {
        log.LogInformation($"# Modified Items:\t{input?.Count ?? 0}");
    
        foreach(Document item in input)
        {
            log.LogInformation($"Detected Operation:\t{item.Id}");
        }
    }
    ```

1. Expand the **Logs** section to connect to the streaming logs for the current function.

    > &#128161; It can take a couple of seconds to connect to the streaming log service. You will see a message in the log output once you are connected.

1. **Save** the current function code.

1. Observe the result of the C# code compilation. You should expect to see a **Compilation succeeded** message at the end of the log output.

    > &#128221; You may see warning messages in the log output. These warnings will not impact this lab.

1. **Maximize** the log section to expand the output window to fill the maximum available space.

    > &#128221; You will use another tool to generate items in your Azure Cosmos DB SQL API container. Once you generate the items, you will return to this browser window to observe the output. Do not close the browser window prematurely.

## Seed your Azure Cosmos DB SQL API account with sample data

You will use a command-line utility that creates a **cosmicworks** database and a **products** container. The tool will then create a set of items that you will observe using the change feed processor running in your terminal window.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

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

1. Close **Visual Studio Code**.

1. Return to the currently open browser window or tab with the Azure Functions log section expanded.

1. Observe the log output from your function. The terminal outputs a **Detected Operation** message for each change that was sent to it using the change feed. The operations are batched into groups of ~100 operations.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/api/microsoft.azure.documents]: https://docs.microsoft.com/dotnet/api/microsoft.azure.documents
[docs.microsoft.com/dotnet/api/microsoft.azure.documents.document]: https://docs.microsoft.com/dotnet/api/microsoft.azure.documents.document
[docs.microsoft.com/dotnet/api/microsoft.azure.documents.resource.id]: https://docs.microsoft.com/dotnet/api/microsoft.azure.documents.resource.id
