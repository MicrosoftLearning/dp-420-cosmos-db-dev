---
lab:
    title: 'Migrate existing data using Azure Data Factory'
    module: 'Module 2 - Plan and implement Azure Cosmos DB SQL API'
---

# Migrate existing data using Azure Data Factory

In Azure Data Factory, Azure Cosmos DB is supported as a source of data ingest and as a target (sink) of data output.

In this lab, we will populate Azure Cosmos DB using a helpful command-line utility and then use Azure Data Factory to move a subset of data from one container to another.

## Create and seed your Azure Cosmos DB SQL API account

You will use a command-line utility that creates a **cosmicworks** database and a **products** container at **4,000** request units per second (RU/s). Once created, you will adjust the throughput down to 400 RU/s.

To accompany the products container, you will create a **flatproducts** container manually that will be the target of the ETL transformation and load operation at the end of this lab.

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

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, expand the **products** container node, and then select **Items**.

1. Observe and select the various JSON items in the **products** container. These are the items created by the command-line tool used in previous steps.

1. Select the **Scale & Settings** node. In the **Scale & Settings** tab, select **Manual**, update the **required throughput** setting from **4000 RU/s** to **400 RU/s** and then **Save** your changes**.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *cosmicworks* |
    | **Container id** | *`flatproducts`* |
    | **Partition key** | *`/category`* |
    | **Container throughput (autoscale)** | *Manual* |
    | **RU/s** | *`400`* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **flatproducts** container node within the hierarchy.

1. Return to the **Home** of the Azure portal.

## Create Azure Data Factory resource

Now that the Azure Cosmos DB SQL API resources are in place, you will create an Azure Data Factory resource and configure all of the necessary components and connections to perform a one-time data movement from one SQL API container to another to extract data, transform it, and load it to another SQL API container.

1. Select **+ Create a resource**, search for *Data Factory*, and then create a new **Azure Data Factory** resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Name** | *Enter a globally unique name* |
    | **Region** | *Choose any available region* |
    | **Version** | *V2* |
    | **Git configuration** | *Configure Git later* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Data Factory** resource and select **Open Azure Data Factory Studio**.

    > &#128161; Alternatively, you can navigate to (``adf.azure.com/home``), select your newly created Data Factory resource, and then select the home icon.

1. From the home screen. Select the **Ingest** option to begin the quick wizard to perform a one-time copy data at scale operation and move to the **Properties** step of the wizard.

1. Starting with the **Properties** step of the wizard, in the **Task type** section, select **Built-in copy task**.

1. In the **Task cadence or task schedule** section, select **Run once now** and then select **Next** to move to the **Source** step of the wizard.

1. In the **Source** step of the wizard, in the **Source type** list, select **Azure Cosmos DB (SQL API)**.

1. In the **Connection** section, select **+ New connection**.

1. In the **New connection (Azure Cosmos DB (SQL API))** popup, configure the new connection with the following values, and then select **Create**:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Name** | *`CosmosSqlConn`* |
    | **Connect via integration runtime** | *AutoResolveIntegrationRuntime* |
    | **Authentication method** | *Account key* &vert; *Connection string* |
    | **Account selection method** | *From Azure subscription* |
    | **Azure subscription** | *Your existing Azure subscription* |
    | **Azure Cosmos DB account name** | *Your existing Azure Cosmos DB account name you chose earlier in this lab* |
    | **Database name** | *cosmicworks* |

1. Back in the **Source data store** section, within the **Source tables** section, select **Use query**.

1. In the **Table name** list, select **products**.

1. In the **Query** editor, delete the existing content and enter the following query:

    ```
    SELECT 
        p.name, 
        p.categoryName as category, 
        p.price 
    FROM 
        products p
    ```

1. Select **Preview data** to test the query's validity. Select **Next** to move to the **Target** step of the wizard.

1. In the **Target** step of the wizard, in the **Target type** list, select **Azure Cosmos DB (SQL API)**.

1. In the **Connection** list, select **CosmosSqlConn**.

1. In the **Target** list, select **flatproducts** and then select **Next** to move to the **Settings** step of the wizard.

1. In the **Settings** step of the wizard, in the **Task name** field, enter **`FlattenAndMoveData`**.

1. Leave all remaining fields to their default blank values and then select **Next** to move to the final step of the wizard.

1. Review the **Summary** of the steps you have selected in the wizard and then select **Next**.

1. Observe the various steps in the deployment. When the deployment has finished, select **Finish**.

1. Close your web browser window or tab.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **Resource groups**, then select the resource group you created or viewed earlier in this lab, and then select the **Azure Cosmos DB account** resource you created in this lab.

1. Within the **Azure Cosmos DB** account resource, navigate to the **Data Explorer** pane.

1. In the **Data Explorer**, expand the **cosmicworks** database node, select the **flatproducts** container node, and then select **New SQL Query**.

1. Delete the contents of the editor area.

1. Create a new SQL query that will return all documents where the **name** is equivalent to **HL Headset**:

    ```
    SELECT 
        p.name, 
        p.category, 
        p.price 
    FROM
        products p
    WHERE
        p.name = 'HL Headset'
    ```

1. Select **Execute Query**.

1. Observe the results of the query.

1. Close your web browser window or tab.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[nuget.org/packages/cosmicworks]: https://www.nuget.org/packages/cosmicworks
