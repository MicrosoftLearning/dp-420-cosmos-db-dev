---
lab:
  title: Design a model and partition strategy
  module: Module 6 - Design a Data Modeling and Partitioning Strategy for Azure Cosmos DB for NoSQL
  description: Model the CosmicWorks entities for a set of access patterns, create a container with a hierarchical partition key, and validate that prefix queries route efficiently.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Design a model and partition strategy

In this exercise, you compare request charges for normalized, embedded, and denormalized models of the CosmicWorks catalog. You then create a container with a hierarchical partition key and compare queries that use different levels of the hierarchy.

Every measurement in this exercise happens in Data Explorer. A setup script provisions the account and loads the sample data, so no application code is required.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

## Set up your Azure Cosmos DB resources

Use the `modeling` profile to create a dedicated account containing four versions of the CosmicWorks data. If your lab provides a resource group, use it.

> &#9888; This exercise deletes its modeling resources when you finish. Keep lab-provided and shared resource groups. Delete only the modeling account when using one of those groups.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI. A browser window opens so you can sign in to Azure.

    ```azurecli
    az login
    ```

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs. Keep a lab-provided group and use the account-only cleanup option at the end.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab06 -LabProfile modeling
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab06a7f3k9`.

1. Wait for the script to finish. The `modeling` profile creates 22 containers across four databases and takes about 10-15 minutes.

1. Record the **Account name** the script prints. You need it to find the account in the Azure portal.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, with key-based authentication disabled |
| `database-v1` | 9 containers, each partitioned on `/id`, holding the relational schema |
| `database-v2` | 5 containers, with customer addresses and credentials embedded |
| `database-v3` | 5 containers, with category and tag names denormalized onto the product |
| `database-v4` | 3 containers, with entity types merged |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Every container is provisioned with autoscale up to 1,000 request units per second (RU/s), and every one is loaded with the CosmicWorks data for its modeling stage.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Confirm the four modeling stages

The CosmicWorks sample publishes the same e-commerce data at four stages of modeling, and this exercise uses all four:

| Database | Model | Containers |
|:---------|:------|:-----------|
| `database-v1` | The relational schema lifted directly into Azure Cosmos DB | 9, each keyed on `/id` |
| `database-v2` | Customer addresses and credentials embedded; product data still referenced | 5 |
| `database-v3` | Category and tag names denormalized onto the product | 5 |
| `database-v4` | Entity types merged: customers with their sales orders, categories with tags | 3 |

1. In a browser, go to the [Azure portal](https://portal.azure.com), select **Azure Cosmos DB**, and select the account the setup script created.

1. On the left pane, select **Data Explorer**, and confirm that **database-v1**, **database-v2**, **database-v3**, and **database-v4** all appear in the tree.

1. Expand **database-v4** and confirm it holds three containers: **customer**, **product**, and **productMeta**.

---

## Task 2: Compare the normalized and embedded customer models

The normalized customer model stores the customer, addresses, and credential in separate containers. Because Azure Cosmos DB doesn't support cross-container joins, the application needs three requests.

### Measure the normalized model

1. Expand **database-v1** and select the **customer** container.

1. At the top of the page, select **New SQL Query**, paste the following query, and select **Execute Query**:

    ```sql
    SELECT * FROM c WHERE c.id = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Select the **Query Stats** tab and record the **Request Charge**. It's about 2.83 request units (RUs).

1. Select the **customerAddress** container, open a new query, and run:

    ```sql
    SELECT * FROM c WHERE c.customerId = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Record the request charge. It's about 2.83 RUs.

1. Select the **customerPassword** container, open a new query, and run:

    ```sql
    SELECT * FROM c WHERE c.id = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Record the request charge. It's about 2.83 RUs.

    | Query | Request charge |
    |:------|:---------------|
    | Customer | 2.83 |
    | Customer address | 2.83 |
    | Customer password | 2.83 |
    | **Total** | **8.49** |

> &#128221; Request charges can vary. Record your own measurements for comparison.

### Measure the embedded model

In `database-v2`, each customer item embeds its address list and credential. These related entities are read together, and their relationships are one-to-one or bounded one-to-few.

1. Expand **database-v2** and select the **customer** container.

1. Open a new query and run the same statement you ran first:

    ```sql
    SELECT * FROM c WHERE c.id = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Select the **Results** tab. The addresses and the credential are now nested inside the customer item.

1. Select **Query Stats** and record the request charge. It's about 2.83 RUs, against 8.49 for the three queries you ran before.

Consider the trade-offs:

- Embedding reduced three queries to one and removed the need to combine results in application code.

- The larger embedded item can increase write costs. Consider how often the customer, addresses, and credential are updated.

> &#128161; A point read retrieves a known item using its ID and partition key. For a 1-KB item, this costs 1 RU at session consistency. The embedded model needs only one point read to return the related data.

---

## Task 3: Measure the cost of denormalizing

Rendering one category page against `database-v2` takes five queries: one for the category name, one for the products in the category, and one for the tag names of each product returned.

### Measure the referenced model

1. Expand **database-v2** and select the **productCategory** container.

1. Open a new query and run:

    ```sql
    SELECT * FROM c WHERE c.type = 'category' AND c.id = "AB952F9F-5ABA-4251-BC2D-AFF8DF412A4A"
    ```

    The result is the category *Components, Headsets*. Record the request charge, about 2.92 RUs.

1. Select the **product** container, open a new query, and run:

    ```sql
    SELECT * FROM c WHERE c.categoryId = "AB952F9F-5ABA-4251-BC2D-AFF8DF412A4A"
    ```

    Three products come back: HL Headset, LL Headset, and ML Headset. Each carries a stock keeping unit (SKU), a name, a price, and an array of tag identifiers rather than tag names. Record the request charge, about 2.89 RUs.

1. To resolve those identifiers into names, select the **productTag** container and run one query per product:

    ```sql
    SELECT * FROM c WHERE c.type = 'tag' AND c.id IN ('87BC6842-2CCA-4CD3-994C-33AB101455F4', 'F07885AF-BD6C-4B71-88B1-F04295992176')
    ```

    ```sql
    SELECT * FROM c WHERE c.type = 'tag' AND c.id IN ('18AC309F-F81C-4234-A752-5DDD2BEAEE83', '1B387A00-57D3-4444-8331-18A90725E98B', 'C6AB3E24-BA48-40F0-A260-CB04EB03D5B0', 'DAC25651-3DD3-4483-8FD1-581DC41EF34B', 'E6D5275B-8C42-47AE-BDEC-FC708DB3E0AC')
    ```

    ```sql
    SELECT * FROM c WHERE c.type = 'tag' AND c.id IN ('A34D34F7-3286-4FA4-B4B0-5E61CCEEE197', 'BA4D7ABD-2E82-4DC2-ACF2-5D3B0DEAE1C1', 'D69B1B6C-4963-4E85-8FA5-6A3E1CD1C83B')
    ```

1. Record each request charge and total them.

    | Query | Request charge |
    |:------|:---------------|
    | Category name | 2.92 |
    | Products in category | 2.89 |
    | HL Headset tags | 3.06 |
    | LL Headset tags | 3.47 |
    | ML Headset tags | 3.20 |
    | **Total** | **15.54** |

    Resolving tag names adds one query per product, increasing both the number of requests and the total RU charge.

### Measure the denormalized model

`database-v3` copies the category name and each tag's name onto the product item.

1. Expand **database-v3** and select the **product** container.

1. Open a new query and run:

    ```sql
    SELECT * FROM c WHERE c.categoryId = "AB952F9F-5ABA-4251-BC2D-AFF8DF412A4A"
    ```

1. Select the **Results** tab. Each product now carries `categoryName`, and its `tags` array now holds the tag name alongside each identifier rather than the identifier alone. Everything the page renders is in this one result.

1. Select **Query Stats** and record the request charge, about 2.89 RUs, against 15.54 for the five queries you ran before.

Five queries became one, reducing the request charge by more than 80 percent in this example. Category and tag names are now duplicated across products, so changes to those names must be synchronized. A category rename requires updating every product in that category.

### Combine entity types into one container

`database-v3` still keeps categories and tags in separate containers, and sales orders in a container of their own. `database-v4` merges each pair, because in both cases the two entity types share a partition key path and an access pattern.

1. Expand **database-v4** and select the **productMeta** container.

1. Open a new query and run:

    ```sql
    SELECT c.type, COUNT(1) AS itemCount FROM c GROUP BY c.type
    ```

    One container now holds 37 items of type `category` and 200 of type `tag`. In `database-v3`, listing both took one query against `productCategory` and another against `productTag`. Here a single query returns either kind, or both, depending on whether you filter on `c.type`.

1. Select the **customer** container in **database-v4**, open a new query, and run:

    ```sql
    SELECT c.type, c.firstName, c.lastName, c.salesOrderCount, c.orderDate
    FROM c
    WHERE c.customerId = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Review the results. The customer item and every sales order that customer placed come back together, because both entity types carry `customerId` and the container is partitioned on it. Everything you see sits in one logical partition.

1. Note the `salesOrderCount` property on the customer item, and count the items of type `salesOrder` in the result. The counts match.

    `salesOrderCount` is a preaggregate: it stores a value that would otherwise be calculated from sales orders. Keeping the customer and orders in one logical partition allows an order insert and counter update to run in a single transaction.

---

## Task 4: Build a subpartitioned container for multiple tenants

The catalog now serves multiple tenants with different data volumes. Partitioning only on `/tenantId` can create uneven logical partitions and limit each tenant to 20 GB.

Create a three-level hierarchical partition key: `/tenantId`, `/categoryId`, `/id`.

The repository's **data/tenant-products.json** contains 295 products with `tenantId` values: 201 for `contoso-outdoors`, 61 for `fabrikam-cycles`, and 33 for `adventure-works`. Each category's products belong to the same tenant.

1. In Data Explorer, select **New Container**.

1. Configure the container:

    | Setting | Value |
    |:--------|:------|
    | **Database id** | *Create new* &vert; `multitenant` |
    | **Container id** | `tenantProduct` |
    | **Partition key** | `/tenantId` |
    | **Container throughput** | *Manual* &vert; `400` |

1. Under the partition key box, select **Add hierarchical partition key** twice, and set the second and third levels to `/categoryId` and `/id`.

    The order of the levels is the order of the hierarchy, and it can't be changed after the container is created.

1. Select **OK** to create the container.

1. Expand **multitenant**, expand **tenantProduct**, and select **Items**.

1. Select **Upload Item**, browse to **data/tenant-products.json** in the cloned repository, and select **Upload**.

1. Confirm that the container reports 295 items.

---

## Task 5: Compare query routing and spot the anti-pattern

Compare queries that use different parts of the hierarchy.

The category `3E4CEACD-D007-46EB-82D7-31F6141752B2` is *Components, Road Frames*. It holds 33 products, and all of them belong to `contoso-outdoors`.

1. With the **tenantProduct** container selected, open a new query and run each of the following queries, recording the request charge and the item count for each.

    A routable prefix naming two levels:

    ```sql
    SELECT * FROM c WHERE c.tenantId = "contoso-outdoors" AND c.categoryId = "3E4CEACD-D007-46EB-82D7-31F6141752B2"
    ```

    A routable prefix naming one level:

    ```sql
    SELECT * FROM c WHERE c.tenantId = "contoso-outdoors"
    ```

    A filter that skips the first level:

    ```sql
    SELECT * FROM c WHERE c.categoryId = "3E4CEACD-D007-46EB-82D7-31F6141752B2"
    ```

    No filter at all:

    ```sql
    SELECT * FROM c
    ```

1. To measure how the data is distributed across first-level key values, run one more query:

    ```sql
    SELECT c.tenantId, COUNT(1) AS itemCount FROM c GROUP BY c.tenantId
    ```

### Interpret the measurements

The largest tenant holds 201 of the 295 products, or about 68 percent of the items. This uneven distribution matters when choosing a partition key.

The tenant-only query returns 201 products; the tenant-and-category query returns 33. Result size also affects RU charges. Use **Retrieved document count** and **Output document count** in Query Stats to compare the work performed.

### Understand routing at larger scale

The category-only query skips `/tenantId`, so it can't use a partition-key prefix for routing. This new container holds 295 small items at 400 RU/s on one physical partition, so you might see little RU difference between the two queries that return 33 items.

With multiple physical partitions, the category-only query can visit all of them, while the prefix query targets only the partitions holding that prefix.

### Review a tenant-only partition key

Suppose `tenantProduct` were partitioned on `/tenantId` alone. Using the distribution you measured, answer three questions:

1. How many logical partitions would the container have, and how much of the data sits in the largest one?
1. Which two of the criteria for a good partition key does that design fail?
1. How does the 20-GB logical partition limit affect `contoso-outdoors` as its catalog grows?

A tenant-only key creates three logical partitions. The largest holds 201 products, or about 68 percent, so the key has low cardinality and uneven distribution. Each tenant is limited to 20 GB in one logical partition; growing beyond that limit requires a new partitioning strategy.

The hierarchical key keeps `/tenantId` as a routing prefix, while the full `/tenantId`, `/categoryId`, `/id` combination defines each logical partition. A tenant's data can therefore span multiple logical and physical partitions.

---

## Clean up resources

The `modeling` profile provisions 22 containers that no other exercise in this learning path uses, so delete them when you finish this exercise rather than at the end of the course.

If you created the dedicated `ResourceGroup1` group and it contains only this exercise's resources, delete that group to stop all charges. Check its contents first:

```azurecli
az resource list --resource-group $resourceGroup --query "[].{Name:name,Type:type}" --output table
az group delete --name $resourceGroup --yes --no-wait
```

If your lab environment provided the resource group, or it holds any other resources, don't run the group deletion. Delete only the modeling account whose name the setup script printed:

```azurecli
az cosmosdb delete --name <your-account-name> --resource-group $resourceGroup --yes
```
