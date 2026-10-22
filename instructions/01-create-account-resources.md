---
lab:
  title: Create an Azure Cosmos DB for NoSQL account
  module: Module 1 - Explore Azure Cosmos DB for NoSQL
  description: Provision an Azure Cosmos DB for NoSQL account and create a database, container, and items.
  duration: 30 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Create an Azure Cosmos DB for NoSQL account

In this exercise, you create an Azure Cosmos DB for NoSQL account, add a database, container, and items in Data Explorer, and query the data. You also use Azure Cloud Shell to grant data access.

This exercise should take approximately **30** minutes to complete.

> &#128221; You need an Azure subscription with permission to create resources and assign Cosmos DB data roles. If you don't have a subscription, create a [free account](https://azure.microsoft.com/free/) before you begin. Provisioned throughput can incur charges, so complete the cleanup steps when you finish.

## Register the Azure Cosmos DB resource provider

Before you can create a resource type, the resource provider that owns it must be registered to your subscription. Azure Cosmos DB belongs to the `Microsoft.DocumentDB` provider, and registration is a one-time step per subscription.

1. In a web browser, open the [Azure portal](https://portal.azure.com) and sign in.

1. In the search bar at the top of the portal, enter *Subscriptions*, and then select **Subscriptions** in the results.

1. Select the subscription you want to use for this exercise.

1. In the resource menu, under **Settings**, select **Resource providers**.

1. In the filter box, enter *DocumentDB*.

1. Select the **Microsoft.DocumentDB** row, and then select **Register** in the toolbar.

1. Select **Refresh** until the **Status** column shows **Registered**. Registration takes a minute or two.

> &#128221; If the status already shows **Registered**, you don't need to register this provider again. Registering this provider requires the `Microsoft.DocumentDB/register/action` permission at the subscription scope. The Owner and Contributor roles include this permission.

If **Microsoft.CloudShell** isn't registered, register it in the same subscription before opening Cloud Shell.

## Create an Azure Cosmos DB for NoSQL account

Choose Azure Cosmos DB for NoSQL. The account's API can't be changed after creation.

1. In the Azure portal, select **Create a resource**, search for *Azure Cosmos DB*, and select **Create** in the results.

1. On **Recommended APIs**, select **Create** under **Azure Cosmos DB for NoSQL**.

1. On the **Basics** tab, enter the following settings, and leave the remaining settings at their default values:

    | Setting | Value |
    |---|---|
    | **Workload Type** | *Learning* |
    | **Subscription** | *Your Azure subscription* |
    | **Resource Group** | `ResourceGroup1`, or your lab-provided group if its name differs |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |

    If you use your own subscription, create `ResourceGroup1` only if it doesn't already exist.

1. Go to the **Security** section of the account-creation process, and for **Key-based authentication**, select **Disable**. The account then accepts only Microsoft Entra ID authentication, which is the recommended approach for new accounts.

1. Select **Review + create**, and after validation passes, select **Create**.

1. Wait for the deployment to finish. This step can take a few minutes.

1. When deployment completes, select **Go to resource** to open your new account.

## Grant yourself access to the data

Azure management roles don't grant access to items. Assign yourself **Cosmos DB Built-in Data Contributor** to read and write data in Data Explorer.

> &#128221; Use Azure CLI to create the role assignment. Your Azure role must allow reading SQL role definitions and managing SQL role assignments. The Owner and Contributor roles include these permissions.

1. In the Azure portal toolbar, select the **Cloud Shell** icon (`>_`) to open Azure Cloud Shell, and choose the **Bash** experience if you're prompted.

    > &#128221; If you haven't set up Cloud Shell, in **Getting started**, select **No storage account required**, select the subscription you use for this exercise, and then select **Apply**. Wait for the Bash prompt before running the following commands.

1. Run the following commands, replacing `<account-name>` with the account you created. If your lab provides a different resource group name, replace `ResourceGroup1` with that name. The third command looks up your own identity:

    ```bash
    RESOURCE_GROUP="ResourceGroup1"
    ACCOUNT_NAME=<account-name>
    PRINCIPAL_ID=$(az ad signed-in-user show --query id --output tsv)
    ```

1. Run the following command to assign yourself the **Cosmos DB Built-in Data Contributor** role, which permits reading and writing items:

    ```bash
    az cosmosdb sql role assignment create \
      --resource-group $RESOURCE_GROUP \
      --account-name $ACCOUNT_NAME \
      --role-definition-id 00000000-0000-0000-0000-000000000002 \
      --principal-id $PRINCIPAL_ID \
      --scope "/"
    ```

1. Wait for the command to finish, then close the Cloud Shell pane.

Allow a few minutes for the role assignment to take effect, then refresh Data Explorer.

## Create a database and container

Use `/categoryId` as the partition key so products with the same category ID share a logical partition.

1. In your account's resource menu, select **Data Explorer**.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** panel, enter the following settings, leave the remaining settings at their default values, and then select **OK**:

    | Setting | Value |
    |---|---|
    | **Database id** | *Create new*, `cosmicworks` |
    | **Container id** | `product` |
    | **Partition key** | `/categoryId` |
    | **Container throughput** | *Manual* |
    | **RU/s** | `400` |

1. In the **Data Explorer** pane, expand the **`cosmicworks`** database node, and confirm that the **product** container appears beneath it.

## Create items

Add two JSON items to the container. Each item is a document, and items in the same container can differ in shape.

1. In the **Data Explorer** pane, expand the **`cosmicworks`** database, expand the **product** container, and then select **Items**.

1. Select **New Item** on the toolbar. Replace the placeholder JSON with the following content:

    ```json
    {
      "categoryId": "4F34E180-384D-42FC-AC10-FEC30227577F",
      "categoryName": "Components, Pedals",
      "sku": "PD-R563",
      "name": "ML Road Pedal",
      "price": 62.09
    }
    ```

1. Select **Save** from the toolbar to add the item. Notice that Data Explorer supplies an `id`, and the service adds system properties.

1. Select **New Item** again, replace the JSON with the following content, and then select **Save**:

    ```json
    {
      "categoryId": "26C74104-40BC-4541-8EF5-9892F7F03D72",
      "categoryName": "Components, Saddles",
      "sku": "SE-R581",
      "name": "LL Road Seat/Saddle",
      "price": 27.12
    }
    ```

1. Select each item in the tree to view its full JSON, including the properties the service added.

## Query your data

Run a query and inspect its request charge.

1. In the **Data Explorer** pane, with the **product** container selected, select **New SQL Query**.

1. Replace the query text with the following statement, and then select **Execute Query**:

    ```sql
    SELECT * FROM product p WHERE p.price > 50
    ```

1. Review the results. The query returns one item, **ML Road Pedal**, because it's the only product priced above 50.

1. Select **Query Stats** and record **Request Charge**, the number of request units (RUs) used by the query.

1. Change the filter to `p.price > 25` and run the query again. Both items match this time, because both prices are above 25.

## Clean up your resources

If you created a new resource group for this exercise and it contains only exercise resources, delete the group when you no longer need it.

1. In the [Azure portal](https://portal.azure.com), open the resource group you created for this exercise.

1. On the toolbar, select **Delete resource group**.

1. Enter the resource group name to confirm, and then select **Delete**.

If you used an existing resource group or the group contains resources you need to keep, delete only the Azure Cosmos DB account you created for this exercise. Open the account in the Azure portal, select **Delete**, and confirm the deletion. Don't delete the resource group.
