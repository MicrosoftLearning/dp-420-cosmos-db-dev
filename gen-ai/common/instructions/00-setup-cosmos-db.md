---
title: 'Setup Azure Cosmos DB'
lab:
    title: 'Setup Azure Cosmos DB'
    module: 'Setup'
layout: default
nav_order: 3
parent: 'Common setup instructions'
---

# Setup Azure Cosmos DB

In this exercise, you will create an Azure Cosmos DB for NoSQL account that you will use throughout the lab modules and grant your user identity access to manage data in the account by assigning it to the **Cosmos DB Built-in Data Contributor** role. This will allow you to use Azure authentication to access the database from your lab code, and avoid needing to store and manage keys.

## Create an Azure Cosmos DB for NoSQL account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you will select which of the APIs you want the account to support. Once the Azure Cosmos DB for NoSQL account is done provisioning, you can retrieve the endpoint and key and use them to connect to the Azure Cosmos DB for NoSQL account using the Azure SDK for Python or any other SDK of your choice.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB for NoSQL** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Serverless* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Copy the **URI** field and save it in a text editor for later. You will use this **endpoint** value later in this exercise.

1. Keep the browser tab open for the next step.

## Provide your user identity the Cosmos DB Built-in Data Contributor RBAC role

As the final task in this exercise, you will grant your Microsoft Entra ID user identity access to manage data in your Azure Cosmos DB for NoSQL account by assigning it to the **Cosmos DB Built-in Data Contributor** RBAC role. This will allow you use Azure authentication to access the database from your code, and avoid needing to store and manage keys.

> &#128221; Utilizing Microsoft Entra ID's Role-Based Access Control (RBAC) for authenticating against Azure services like Azure Cosmos DB presents several primary benefits over key-based methods. Entra ID RBAC enhances security through precise access controls tailored to user roles, effectively reducing unauthorized access risks. It also streamlines user management, enabling administrators to dynamically assign and modify permissions without the hassle of distributing and maintaining cryptographic keys. Furthermore, this approach enhances compliance and auditability by aligning with organizational policies and facilitating comprehensive access monitoring and review. By streamlining secure access management, Entra ID RBAC makes a more efficient and scalable solution for leveraging Azure services.

1. From the toolbar in the [Azure portal](https://portal.azure.com), open a Cloud Shell.

    ![The Cloud Shell icon is highlighted on the Azure portal's toolbar.](media/azure-portal-toolbar-cloud-shell.png)

1. At the Cloud Shell prompt, ensure your exercise subscription is used for subsequent commands by running `az account set -s <SUBSCRIPTION_ID>`, replacing the `<SUBSCRIPTION_ID>` placeholder token with the id of the subscription you are using for this exercise.

1. Copy the output of the above command for use as the `<PRINCIPAL_OBJECT_ID>` token in the `az cosmosdb sql role assignment create` command below.

1. Next, you will retrieve the definition id of the **Cosmos DB Built-in Data Contributor** role. Run the following command, ensuring you replace the `<RESOURCE_GROUP_NAME>` and `<COSMOS_DB_ACCOUNT_NAME>` tokens.

    ```bash
    az cosmosdb sql role definition list --resource-group "<RESOURCE_GROUP_NAME>" --account-name "<COSMOS_DB_ACCOUNT_NAME>"
    ```

    Review the output and locate the role definition named **Cosmos DB Built-in Data Contributor**. The output contains the unique identifier of the role definition in the `name` property. Record this value as it is required to use in the assignment step later in the next step.

1. You are now ready to assign yourself to the **Cosmos DB Built-in Data Contributor** role definition. Enter the following command at the prompt, making sure to replace the `<RESOURCE_GROUP_NAME>` and `<COSMOS_DB_ACCOUNT_NAME>` tokens.

    > &#128221; In the command below, the `role-definition-id` is set to `00000000-0000-0000-0000-000000000002`, which is the default value for the **Cosmos DB Built-in Data Contributor** role definition. If the value you retrieved from the `az cosmosdb sql role definition list` command differs, replace the value in the command below before execution. The `az ad signed-in-user show` command retrieves the object ID of the signed-in Entra ID user.

    ```bash
    az cosmosdb sql role assignment create --resource-group "<RESOURCE_GROUP_NAME>" --account-name "<COSMOS_DB_ACCOUNT_NAME>" --role-definition-id "00000000-0000-0000-0000-000000000002" --principal-id $(az ad signed-in-user show --query id -o tsv) --scope "/"
    ```

1. When the command finishes running, you will be able to run code locally to insert interact with data stored into the your Cosmos DB NoSQL database.

1. Close the Cloud Shell.
