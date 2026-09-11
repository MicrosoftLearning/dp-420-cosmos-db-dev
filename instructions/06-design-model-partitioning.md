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

In this exercise, you measure what a data model costs and then build the partitioning strategy that lets it scale. You compare the request charge of assembling a customer from three containers against reading the same customer as one embedded item. You compare the cost of rendering a product page from four containers against reading it from one denormalized container. Then you create a subpartitioned container for a multitenant catalog and measure how query routing changes depending on which levels of the hierarchy a query names.

Every measurement in this exercise happens in Data Explorer. A setup script provisions the account and loads the sample data, so no application code is required.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

## Set up your Azure Cosmos DB resources

This exercise needs the CosmicWorks data at four stages of modeling, which the other exercises in this learning path don't provision. Run the setup script with the `modeling` profile to create a dedicated account, even if you already have an account from an earlier exercise. Use the resource group supplied by your lab environment.

> [!WARNING]
> This exercise deletes its modeling resources when you finish. Keep lab-provided and shared resource groups. Delete only the modeling account when using one of those groups.

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

1. Wait for the script to finish. The `modeling` profile creates 22 containers across four databases, so it takes 10-15 minutes, longer than the other exercises in this learning path.

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

> [!NOTE]
> A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

---

## Task 1: Confirm the four modeling stages

The CosmicWorks sample publishes the same e-commerce data at four stages of modeling, and this exercise uses all four:

| Database | Model | Containers |
|:---------|:------|:-----------|
| `database-v1` | The relational schema lifted directly into Azure Cosmos DB | 9, each keyed on `/id` |
| `database-v2` | Customer addresses and credentials embedded; product data still referenced | 5 |
| `database-v3` | Category and tag names denormalized onto the product | 5 |
| `database-v4` | Entity types merged: customers with their sales orders, categories with tags | 3 |

Each stage is a step in the same design process, so you measure the cost of one model and then the cost of the next.

1. In a browser, go to the [Azure portal](https://portal.azure.com), select **Azure Cosmos DB**, and select the account the setup script created.

1. On the left pane, select **Data Explorer**, and confirm that **database-v1**, **database-v2**, **database-v3**, and **database-v4** all appear in the tree.

1. Expand **database-v4** and confirm it holds three containers: **customer**, **product**, and **productMeta**. That's the model this module designed, and the rest of the exercise measures the steps that led to it.

---

## Task 2: Compare the normalized and embedded customer models

When a customer signs in to the CosmicWorks store, the application needs the customer record, that customer's addresses, and the stored credential. The normalized model keeps each one in its own container. Azure Cosmos DB can't join across containers, so the application sends three separate requests to build one sign-in.

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

> [!NOTE]
> Your figures vary slightly from run to run and from account to account, usually within a range of 0.1 RU. Record what you measure rather than the number we published here.

### Measure the embedded model

`database-v2` embeds the address list and the credential into the customer item, exactly as the embed-or-reference rules in this module prescribe: the entities are read together, one relationship is one-to-one, and the other is bounded one-to-few.

1. Expand **database-v2** and select the **customer** container.

1. Open a new query and run the same statement you ran first:

    ```sql
    SELECT * FROM c WHERE c.id = "44A6D5F6-AF44-4B34-8AB5-21C5DC50926E"
    ```

1. Select the **Results** tab. The addresses and the credential are now nested inside the customer item.

1. Select **Query Stats** and record the request charge. It's about 2.83 RUs, against 8.49 for the three queries you ran before.

Two notes are worth reviewing before you move on.

- The saving comes from **request count**, not from a cheaper query. One request replaced three, so the latency is one round trip rather than three sequential ones, and the application needs no code to stitch the pieces together.

- The embedded item is larger than any single item in the normalized model. That cost lands on writes, which is the trade you accepted. A profile update now rewrites the addresses and the credential too.

> [!TIP]
> An application that knows both the item identifier and the partition key can read this item with a point read rather than a query. A point read of a 1-KB item costs 1 RU, and the charge rises with item size from there. Data Explorer runs queries, not point reads. Therefore, you can't measure the request charge for a point read here. A point read is the least expensive way to retrieve a known item. Embedding allows one point read to return all required data under one identifier.

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

    Notice that the tag queries dominate. The cost increases with the number of products on the page. It also increases with the number of tags for each product. As the catalog grows, the page becomes slower and more expensive.

### Measure the denormalized model

`database-v3` copies the category name and each tag's name onto the product item.

1. Expand **database-v3** and select the **product** container.

1. Open a new query and run:

    ```sql
    SELECT * FROM c WHERE c.categoryId = "AB952F9F-5ABA-4251-BC2D-AFF8DF412A4A"
    ```

1. Select the **Results** tab. Each product now carries `categoryName`, and its `tags` array now holds the tag name alongside each identifier rather than the identifier alone. Everything the page renders is in this one result.

1. Select **Query Stats** and record the request charge, about 2.89 RUs, against 15.54 for the five queries you ran before.

Five requests became one, and the cost fell by more than 80 percent. The price of that saving is a synchronization obligation: when a category is renamed, every product carrying the old `categoryName` is wrong until something updates it. That update is the job the change feed does, and the write cost of a rename is now proportional to how many items carry the copy.

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

    That property is a preaggregate. Ranking customers by order count would otherwise scan every customer in the container, so the model stores the answer instead of computing it. Keeping it correct is what makes the merge necessary: an order insert and the counter increment have to succeed or fail together, and Azure Cosmos DB provides that guarantee only within a single logical partition.

---

## Task 4: Build a subpartitioned container for multiple tenants

Contoso now hosts catalogs for several retail brands. Partitioning on the tenant alone is the intuitive choice and the one that fails first: tenants are wildly uneven, and the largest reaches the 20-GB logical partition ceiling while the others sit nearly empty.

This task builds the alternative from the hierarchical partition keys unit: a three-level key of `/tenantId`, `/categoryId`, `/id`.

The `tenantId` property doesn't exist in the CosmicWorks data, because the sample models a single retailer. The lab repository includes a tagged copy of the product data at **data/tenant-products.json**, which assigns every product in a category to the same tenant: 201 products to `contoso-outdoors`, 61 to `fabrikam-cycles`, and 33 to `adventure-works`. The skew is deliberate.

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

The reason to order a hierarchy around access patterns is routing. This task runs the same catalog query four ways, changing only which levels of the hierarchy the filter names.

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

### What the numbers show

**The distribution is the finding.** The container reports 201 items for `contoso-outdoors`, 61 for `fabrikam-cycles`, and 33 for `adventure-works`. One first-level key value holds 68 percent of the data. That measurement is the anti-pattern this module warns about, made concrete: it's the same shape a real platform sees when one tenant dwarfs the others, and it's visible at 295 items exactly as it is at 295 million.

**Request charge tracks items evaluated, not partitions.** The tenant-only query returns 201 items and costs noticeably more than the tenant-and-category query returning 33. Narrowing the filter down the hierarchy cuts the charge, because the engine reads less, which the **Retrieved document count** and **Output document count** rows in Query Stats show directly.

### What this container is too small to show

The third query, filtering on category alone, skips the first level of the hierarchy and can't be routed. It costs about what the routable query costs, which is correct rather than a mistake in your setup.

Your container holds 295 small items, which fits in a single physical partition. A query that can't be routed fans out to every physical partition, and here there's exactly one, so there's nothing to fan out to. Fan-out is invisible at this scale by definition.

The cost is arithmetic rather than mystery. Each extra physical partition a query has to check adds two to three RUs before it reads a single item. A container spread across 100 physical partitions charges 200 to 300 RUs of pure overhead on the category-only query, while the tenant-prefixed query still reaches only the partitions holding that tenant. A container needs about 5 TB of data to reach 100 physical partitions. Alternatively, it needs 1,000,000 RU/s of provisioned throughput. This lab can demonstrate data skew, but it can't demonstrate fan-out at that scale.

The design lesson survives the scale gap: you can measure distribution on day one, and distribution is what determines whether fan-out ever becomes your problem.

### Review the design you didn't ship

Suppose `tenantProduct` were partitioned on `/tenantId` alone. Using the distribution you measured, answer three questions:

1. How many logical partitions would the container have, and how much of the data sits in the largest one?
1. Which two of the criteria for a good partition key does that design fail?
1. What happens to `contoso-outdoors` as its catalog grows, and at what point does it stop being a performance problem and start being an outage?

The design has three logical partitions, and your own output shows one of them holding 68 percent of the items. This key has low cardinality and distributes data unevenly. It sends all writes for a tenant to one logical partition. As a result, the partition receives all write throughput for that tenant. When `contoso-outdoors` reaches 20 GB, writes for that tenant stop, and the fix at that point is a container migration rather than a configuration change.

The hierarchy you built avoids all three outcomes. The first level still groups a tenant's data for routing, while the deeper levels let one tenant's data spread across as many physical partitions as it needs.

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
