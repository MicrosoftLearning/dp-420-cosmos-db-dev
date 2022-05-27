---
lab:
    title: 'Configure throughput for Azure Cosmos DB SQL API with the Azure portal'
    module: 'Module 2 - Plan and implement Azure Cosmos DB SQL API'
---

# Configure throughput for Azure Cosmos DB SQL API with the Azure portal

One of the most important things to wrap your head around is configuring throughput in Azure Cosmos DB SQL API. To create an Azure Cosmos DB SQL API container, you must first create an account and then a database; in that order.

In this lab, you will provision throughput using various methods in the Data Explorer. You will provision throughput either manually or using autoscale, at the database and the container level.

## Create a serverless account

Let’s start simple by creating a serverless account. There’s not much to configure here since everything is serverless. When we create our database and container, we don’t have to provision throughput at all. You will see all of that as we step into creating this account.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Within the **Azure services** category, select **Create a resource**, and then select **Azure Cosmos DB**.

    > &#128161; Alternatively; expand the **&#8801;** menu, select **All Services**, in the **Databases** category, select **Azure Cosmos DB**, and then select **Create**.

1. In the **Select API option** pane, select the **Create** option within the **Core (SQL) - Recommended** section.

1. Within the **Create Azure Cosmos DB Account** pane, observe the **Basics** tab.

1. On the **Basics** tab, enter the following values for each setting:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Subscription** | *All resources must belong to a resource group. Every resource group must belong to a subscription. Here, use your existing Azure subscription.* |
    | **Resource Group** | *All resources must belong to a resource group. Here, select an existing or create a new resource group.* |
    | **Account Name** | *The globally unique account name. This name will be used as part of the DNS address for requests. Enter any globally unique name. The portal will check the name in real time.* |
    | **Location** | *Select the geographical region from which your database will initially be hosted. Choose any available region.* |
    | **Capacity mode** | *Select Serverless* |

1. Select **Review + Create** to navigate to the **Review + Create** tab, and then select **Create**.

    > &#128221; It can take 10-15 minutes for the Azure Cosmos DB SQL API account to be ready for use.

1. Observe the **Deployment** pane. When the deployment is complete, the pane will update with a **Deployment successful** message.

1. Still within the **Deployment** pane, select **Go to resource**.

1. From within the **Azure Cosmos DB account** pane, select **Data Explorer** from the resource menu.

1. In the **Data Explorer** pane, expand **New Container** and then select **New Database**.

1. In the **New Database** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *`cosmicworks`* |

1. Back in the **Data Explorer** pane, observe the **cosmicworks** database node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *cosmicworks* |
    | **Container id** | *`products`* |
    | **Partition key** | *`/categoryId`* |

1. Back in the **Data Explorer** pane, expand the **cosmicworks** database node and then observe the **products** container node within the hierarchy.

1. Return to the **Home** of the Azure portal.

## Create a provisioned account

Now, we are going to create a provisioned throughput account with more traditional configuration options. This type of account will open up a world of configuration options for us which can be a bit overwhelming. We are going to walk through a few examples of database and container pairings that are possible here.

1. Within the **Azure services** category, select **Create a resource**, and then select **Azure Cosmos DB**.

    > &#128161; Alternatively; expand the **&#8801;** menu, select **All Services**, in the **Databases** category, select **Azure Cosmos DB**, and then select **Create**.

1. In the **Select API option** pane, select the **Create** option within the **Core (SQL) - Recommended** section.

1. Within the **Create Azure Cosmos DB Account** pane, observe the **Basics** tab.

1. On the **Basics** tab, enter the following values for each setting:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Subscription** | *All resources must belong to a resource group. Every resource group must belong to a subscription. Here, use your existing Azure subscription.* |
    | **Resource Group** | *All resources must belong to a resource group. Here, select an existing or create a new resource group.* |
    | **Account Name** | *The globally unique account name. This name will be used as part of the DNS address for requests. Enter any globally unique name. The portal will check the name in real time.* |
    | **Location** | *Select the geographical region from which your database will initially be hosted. Choose any available region.* |
    | **Capacity mode** | *Select provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |
    | **Limit the total amount of throughput that can be provisioned on this account** | *Unchecked* |

1. Select **Review + Create** to navigate to the **Review + Create** tab, and then select **Create**.

    > &#128221; It can take 10-15 minutes for the Azure Cosmos DB SQL API account to be ready for use.

1. Observe the **Deployment** pane. When the deployment is complete, the pane will update with a **Deployment successful** message.

1. Still within the **Deployment** pane, select **Go to resource**.

1. From within the **Azure Cosmos DB account** pane, select **Data Explorer** from the resource menu.

1. In the **Data Explorer** pane, expand **New Container** and then select **New Database**.

1. In the **New Database** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *`nothroughputdb`* |
    | **Provision throughput** | *Do not select* |

1. Back in the **Data Explorer** pane, observe the **nothroughputdb** database node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *nothroughputdb* |
    | **Container id** | *`requiredthroughputcontainer`* |
    | **Partition key** | *`/primarykey`* |
    | **Container throughput** | *Manual* |
    | **RU/s** | *`400`* |

1. Back in the **Data Explorer** pane, expand the **nothroughputdb** database node and then observe the **requiredthroughputcontainer** container node within the hierarchy.

1. In the **Data Explorer** pane, expand **New Container** and then select **New Database**.

1. In the **New Database** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *`manualthroughputdb`* |
    | **Provision throughput** | *Select this option* |
    | **Database throughput** | *Manual* |
    | **RU/s** | *`400`* |

1. Back in the **Data Explorer** pane, observe the **manualthroughputdb** database node within the hierarchy.

1. In the **Data Explorer** pane, select **New Container**.

1. In the **New Container** popup, enter the following values for each setting, and then select **OK**:

    | **Setting** | **Value** |
    | --: | :-- |
    | **Database id** | *Use existing* &vert; *manualthroughputdb* |
    | **Container id** | *`childcontainer`* |
    | **Partition key** | *`/primarykey`* |
    | **Provision dedicated throughput for this container** | *Select this option* |
    | **Container throughput** | *Manual* |
    | **RU/s** | *`1000`* |

1. Back in the **Data Explorer** pane, expand the **manualthroughputdb** database node and then observe the **childcontainer** container node within the hierarchy.
