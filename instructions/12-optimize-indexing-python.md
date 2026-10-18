---
lab:
  title: Optimize an indexing strategy in Python
  module: Module 12 - Design and Optimize an Indexing Strategy in Azure Cosmos DB
  description: Measure index-maintenance cost, enable composite and computed-property queries, query a spatial index, and verify a global secondary index.
  duration: 75 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Optimize an indexing strategy in Python

In this exercise, you optimize indexing on a CosmicWorks product catalog. You measure index-maintenance cost, add composite and computed-property indexes, query a spatial index, and verify a global secondary index (GSI).

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You also need [Python](https://www.python.org/downloads/) 3.12 or 3.13 installed.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path.

Global secondary indexes require continuous backup on the account, and moving an account to continuous backup can't be undone, which is why this exercise provisions an account of its own rather than changing a shared one.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**.

1. Sign in to the Azure CLI and follow the sign-in prompts for your environment.

    ```azurecli
    az login
    ```

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "westus2"
    ```

1. Run the setup script.

    ```powershell
    .\setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab12 -LabProfile indexing
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab12a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need the endpoint later in this exercise, and it looks like `https://<your-account-name>.documents.azure.com:443/`.

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, continuous backup at the `Continuous7Days` tier, with key-based authentication disabled |
| `cosmicworks` database | Holds the containers this exercise uses |
| `product` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, loaded with 295 CosmicWorks database-v4 products |
| `productMeta` container | Partitioned on `/type`, autoscale up to 1,000 RU/s, loaded with 237 database-v4 category and tag documents |
| `indexingLab` container | Partitioned on `/categoryId`, autoscale up to 1,000 RU/s, left empty for the lab fixtures |
| Role assignment | Cosmos DB Built-in Data Contributor, granted to your signed-in identity |

Task 6 adds a fourth container for the GSI. Throughput and storage charges apply.

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. Every operation authenticates with the identity from your `az login` session, which is the recommended approach for new accounts.

> &#9888; Use only the account this script creates for this exercise, not an account from an earlier indexing run. Existing policies or a GSI invalidate the before-and-after tests.

> &#128221; A new role assignment takes a few minutes to propagate. If a later step fails with a 403 error, wait a moment and try again.

1. Set variables for the account name and endpoint, then verify the resources:

    ```powershell
    $accountName = "<your-account-name>"
    $env:COSMOS_ENDPOINT = "<your-account-endpoint>"
    .\verify.ps1 -ResourceGroup $resourceGroup -AccountName $accountName -LabProfile indexing
    ```

## Task 1: Create a write-cost experiment

1. In the same terminal, create your application folder and install the SDKs:

    ```powershell
    mkdir indexing-lab
    Set-Location indexing-lab
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install azure-cosmos==4.17.1 azure-identity==1.26.0
    ```

1. Create **measure.py** with the following code. The probe attaches the 200 real catalog tags to a sandbox copy, making unused index entries measurable without changing the original product.

    ```python
    import json
    import os
    import time
    from azure.cosmos import CosmosClient
    from azure.identity import AzureCliCredential

    CATEGORY_ID = "AE48F0AA-4F65-4734-A4CF-D48B8F82267F"
    PRODUCT_ID = "FD48A179-6CF5-45F2-8605-9DA19B9D4409"
    SKU = "BK-R93R-44"
    # Use the identity from az login; these clients reference existing resources.
    client = CosmosClient(os.environ["COSMOS_ENDPOINT"], AzureCliCredential())
    database = client.get_database_client("cosmicworks")
    product = database.get_container_client("product")
    sandbox = database.get_container_client("indexingLab")
    metadata = database.get_container_client("productMeta")


    def business_item(item):
        # Keep business fields, but don't send server-managed metadata back.
        return {key: value for key, value in item.items() if not key.startswith("_")}


    def measure(container, text, parameters=None, partition_key=None):
        # Supplying a key scopes the request to one logical partition.
        options = {"enable_cross_partition_query": partition_key is None}
        if partition_key is not None:
            options["partition_key"] = partition_key
        rows, charge = [], 0.0
        pages = container.query_items(query=text, parameters=parameters or [], **options).by_page()
        for page in pages:
            # Queries are lazy: consume each page before reading its request charge.
            rows.extend(list(page))
            charge += float(container.client_connection.last_response_headers["x-ms-request-charge"])
        return rows, charge


    def replace_charge(container, item):
        charge = 0.0
        # Average three identical replacements; setup writes aren't included.
        for _ in range(3):
            headers = {}
            container.replace_item(
                item=item["id"], body=item,
                response_hook=lambda response_headers, body: headers.update(response_headers),
            )
            charge += float(headers["x-ms-request-charge"])
        return charge / 3


    def index_ready(container):
        headers = {}
        # A policy update can finish before its new indexes are ready for queries.
        container.read(
            populate_quota_info=True,
            response_hook=lambda response_headers, body: headers.update(response_headers),
        )
        progress = int(headers["x-ms-documentdb-collection-index-transformation-progress"])
        print(f"Index transformation: {progress}%")
        return progress == 100


    def wait_for_rows(container, text, parameters, expected, partition_key=None):
        # GSI propagation is asynchronous; poll actual data with a bounded wait.
        deadline = time.monotonic() + 900
        while True:
            rows, _ = measure(container, text, parameters, partition_key)
            if rows == expected:
                return
            if time.monotonic() >= deadline:
                raise TimeoutError("Expected GSI data didn't arrive within 15 minutes.")
            time.sleep(5)


    # TASK CODE
    source = business_item(product.read_item(item=PRODUCT_ID, partition_key=CATEGORY_ID))
    tags, _ = measure(
        metadata, "SELECT c.id, c.name FROM c WHERE c.type = @type",
        [{"name": "@type", "value": "tag"}], partition_key="tag",
    )
    if len(tags) != 200:
        raise ValueError("Expected 200 tags. Check the indexing profile's productMeta data.")
    # Stable ordering keeps the before/after replacement bodies identical.
    tags.sort(key=lambda tag: tag["id"])
    # Expand tags only in the sandbox to expose unused index-maintenance work.
    probe = {**source, "id": "indexing-write-probe", "labPurpose": "write-probe", "tags": tags}
    # Prepare the probe first; its upsert charge isn't part of the replace average.
    sandbox.upsert_item(probe)
    rows, charge = measure(
        sandbox, "SELECT c.sku, c.name, c.price FROM c WHERE c.id = @id AND c.sku = @sku",
        [{"name": "@id", "value": probe["id"]}, {"name": "@sku", "value": SKU}],
        partition_key=CATEGORY_ID,
    )
    print(f"Probe: {len(probe['tags'])} tags, {len(json.dumps(probe).encode())} bytes")
    print(f"SKU lookup: {charge:.2f} RU for {len(rows)} items")
    print(f"Probe replace: {replace_charge(sandbox, probe):.2f} RU")
    ```

1. Run the application:

    ```powershell
    python measure.py
    ```

    Record **Probe replace** as **before trimming**. The SKU lookup should return one item.

## Task 2: Exclude unused index paths

1. Create **index-policy.json** in your application folder. Include the root and exclude the unused description and tag paths:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [{ "path": "/*" }],
      "excludedPaths": [
        { "path": "/description/?" },
        { "path": "/tags/*" },
        { "path": "/\"_etag\"/?" }
      ]
    }
    ```

1. Apply the policy to the sandbox, then run the **unchanged** program:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name indexingLab --idx "@index-policy.json"
    python measure.py
    ```

    **Compare:** Probe replace should cost less than **before trimming**, while the lookup still returns the same product. Don't change the probe or query between these measurements.

## Task 3: Add a composite index

1. In **measure.py**, replace everything from `# TASK CODE` to the end of the file with this block. Keep the imports, clients, constants, and functions above it unchanged. Use this same replacement rule for later Python blocks.

    ```python
    # TASK CODE
    if not index_ready(product):
        raise SystemExit("Wait, then run measure.py again.")
    # Both ORDER BY paths must match a composite index, in this sequence.
    rows, charge = measure(
        product,
        "SELECT c.id, c.sku, c.price FROM c WHERE c.categoryId = @categoryId "
        "ORDER BY c.categoryId, c.price DESC",
        [{"name": "@categoryId", "value": CATEGORY_ID}], partition_key=CATEGORY_ID,
    )
    print(f"{len(rows)} products; {charge:.2f} RU")
    print(json.dumps(rows[:3], indent=2))
    ```

1. Run `python measure.py`. Expect HTTP **400** stating that the two-property `ORDER BY` needs a composite index. Other errors aren't the expected result.

1. Create **product-policy.json**. Keep the catalog's range indexes and add the composite in query order:

    ```json
    {
      "indexingMode": "consistent",
      "automatic": true,
      "includedPaths": [{ "path": "/*" }],
      "excludedPaths": [{ "path": "/\"_etag\"/?" }],
      "compositeIndexes": [[
        { "path": "/categoryId", "order": "ascending" },
        { "path": "/price", "order": "descending" }
      ]]
    }
    ```

1. Apply it and run the **same query**, unchanged:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name product --idx "@product-policy.json"
    python measure.py
    ```

    If progress is below **100%**, wait and rerun the program.

    Confirm **43** products in descending price order. The matching composite index lets the catalog run this category-and-price sort without changing the query.

## Task 4: Define and index a computed property

1. In the terminal, create the computed-property object and container definition. Load your existing product policy so the composite index is retained.

    ```powershell
    $subscriptionId = (az account show --query id --output tsv)
    $accountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$accountName"
    $containerId = "$accountId/sqlDatabases/cosmicworks/containers/product"
    # Derive the category without adding a stored product field.
    $computedProperty = @{
        name = "cp_primaryCategory"
        query = "SELECT VALUE SUBSTRING(c.categoryName, 0, INDEX_OF(c.categoryName, ',')) FROM c"
    }
    $containerDefinition = @{
        location = $location
        properties = @{
            resource = @{
                id = "product"
                partitionKey = @{ paths = @("/categoryId"); kind = "Hash"; version = 2 }
                # Retain the composite index when replacing the container definition.
                indexingPolicy = (Get-Content -Raw .\product-policy.json | ConvertFrom-Json)
                computedProperties = @($computedProperty)
            }
        }
    }
    $containerDefinition | ConvertTo-Json -Depth 30 | Set-Content .\product-definition.json -Encoding utf8
    # Use ARM for container changes; the application keeps keyless SDK data access.
    az rest --method PUT --uri "https://management.azure.com${containerId}?api-version=2025-04-15" --body "@product-definition.json"
    az resource wait --ids $containerId --api-version 2025-04-15 `
        --custom "properties.resource.computedProperties[0].name == 'cp_primaryCategory'" --interval 5 --timeout 900
    ```

    Container changes use the management API because keyless authentication doesn't authorize SDK container replacement.

1. Replace the Python task-code block with:

    ```python
    # TASK CODE
    if not index_ready(product):
        raise SystemExit("Wait, then run measure.py again.")
    # Select the derived value explicitly; SELECT * omits computed properties.
    # ORDER BY also needs the explicit /cp_primaryCategory/? index path.
    rows, charge = measure(
        product, "SELECT c.sku, c.cp_primaryCategory FROM c ORDER BY c.cp_primaryCategory",
    )
    print(f"{len(rows)} products; {charge:.2f} RU")
    print(sorted({row["cp_primaryCategory"] for row in rows}))
    ```

1. Run `python measure.py`. Expect HTTP **400** for the missing order-by index. The root wildcard doesn't index computed properties.

1. In **product-policy.json**, replace only the `includedPaths` array value with the following. Keep its following comma and the other properties unchanged:

    ```json
    [
      { "path": "/*" },
      { "path": "/cp_primaryCategory/?" }
    ]
    ```

1. Update the definition with the edited policy and submit it:

    ```powershell
    # Update only the policy, preserving the computed definition in the ARM object.
    $containerDefinition.properties.resource.indexingPolicy = Get-Content -Raw .\product-policy.json | ConvertFrom-Json
    $containerDefinition | ConvertTo-Json -Depth 30 | Set-Content .\product-definition.json -Encoding utf8
    az rest --method PUT --uri "https://management.azure.com${containerId}?api-version=2025-04-15" --body "@product-definition.json"
    az resource wait --ids $containerId --api-version 2025-04-15 `
        --custom "properties.resource.indexingPolicy.includedPaths[?path=='/cp_primaryCategory/?']" --interval 5 --timeout 900
    python measure.py
    ```

    Rerun after progress reaches **100%**. **Check:** 295 products sort into Accessories, Bikes, Clothing, and Components.

## Task 5: Create GeoJSON objects and a spatial index

1. In the sandbox's **index-policy.json**, add this property after `excludedPaths`, inserting the separating comma:

    ```json
    "spatialIndexes": [
      { "path": "/location/*", "types": ["Point"] }
    ]
    ```

1. Apply the edited policy:

    ```powershell
    az cosmosdb sql container update `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name indexingLab --idx "@index-policy.json"
    ```

1. Replace the Python task-code block with the following. These are sandbox copies with **lab-only coordinates**, not geocoded CosmicWorks addresses:

    ```python
    # TASK CODE
    if not index_ready(sandbox):
        raise SystemExit("Wait, then run measure.py again.")
    source = business_item(product.read_item(item=PRODUCT_ID, partition_key=CATEGORY_ID))
    # GeoJSON Point coordinates are longitude first, then latitude.
    locations = [
        ("Seattle", [-122.33, 47.60]),
        ("Bellevue", [-122.2015, 47.6101]),
        ("Boston", [-71.06, 42.36]),
    ]
    for city, coordinates in locations:
        item = {
            **source,
            "id": f"spatial-{city.lower()}",
            "labPurpose": "spatial",
            "fulfillmentCity": city,
            "location": {"type": "Point", "coordinates": coordinates},
        }
        # Keep these test locations in the sandbox, not the original catalog.
        sandbox.upsert_item(item)
    # ST_DISTANCE uses meters: 25,000 meters is a 25-km search radius.
    rows, charge = measure(
        sandbox,
        'SELECT c.fulfillmentCity FROM c WHERE c.labPurpose = "spatial" '
        'AND ST_DISTANCE(c.location, {"type":"Point","coordinates":[-122.33,47.60]}) < 25000',
        partition_key=CATEGORY_ID,
    )
    print(f"Within 25 km: {sorted(row['fulfillmentCity'] for row in rows)}; {charge:.2f} RU")
    ```

1. Run `python measure.py`, repeating if progress is below **100%**. **Check:** Seattle and Bellevue match; Boston doesn't. GeoJSON coordinates use longitude, then latitude.

## Task 6: Create and query a global secondary index

1. Replace the Python task-code block and run `python measure.py`:

    ```python
    # TASK CODE
    # Capture the source-write baseline before the GSI adds synchronization work.
    source = business_item(product.read_item(item=PRODUCT_ID, partition_key=CATEGORY_ID))
    print(f"Source replace before GSI: {replace_charge(product, source):.2f} RU")
    ```

    Record **Source replace before GSI**. Use this value, not the sandbox measurement from Task 1.

1. Create **capabilities.json**:

    ```json
    { "properties": { "enableMaterializedViews": true } }
    ```

1. Enable the feature and wait for the account update:

    ```powershell
    # The account API still calls the GSI feature enableMaterializedViews.
    az rest --method PATCH --uri "https://management.azure.com${accountId}?api-version=2022-11-15-preview" --body "@capabilities.json"
    if ($LASTEXITCODE -ne 0) { throw "The feature update failed. Check the error above." }
    az resource wait --ids $accountId --api-version 2022-11-15-preview `
        --custom "properties.enableMaterializedViews && properties.provisioningState == 'Succeeded'" --interval 10 --timeout 900
    if ($LASTEXITCODE -ne 0) { throw "The feature check failed. Stop here." }
    ```

1. Create **gsi-definition.json**, using the region you selected during setup for `location`:

    ```json
    {
      "location": "westus2",
      "properties": {
        "resource": {
          "id": "productBySku",
          "partitionKey": { "paths": ["/sku"], "kind": "Hash", "version": 2 },
          "materializedViewDefinition": {
            "sourceCollectionId": "product",
            "definition": "SELECT c.id, c.sku, c.name, c.price, c.categoryId FROM c"
          }
        },
        "options": { "autoscaleSettings": { "maxThroughput": 1000 } }
      }
    }
    ```

1. Create the index container:

    ```powershell
    $gsiId = "$accountId/sqlDatabases/cosmicworks/containers/productBySku"
    az rest --method PUT --uri "https://management.azure.com${gsiId}?api-version=2022-11-15-preview" --body "@gsi-definition.json"
    if ($LASTEXITCODE -ne 0) { throw "Couldn't create productBySku. Check the error above." }
    az resource wait --exists --ids $gsiId --api-version 2022-11-15-preview --interval 5 --timeout 900
    if ($LASTEXITCODE -ne 0) { throw "Could not confirm productBySku exists. Stop here." }
    $createdIndex = az cosmosdb sql container show `
        --resource-group $resourceGroup --account-name $accountName `
        --database-name cosmicworks --name productBySku --query "resource.id" --output tsv
    if ($LASTEXITCODE -ne 0 -or $createdIndex -cne "productBySku") {
        throw "Couldn't find productBySku in this account. Stop here."
    }
    Write-Host "Created productBySku."
    ```

    Confirm **Created productBySku.** appears before continuing. The application waits for data only after the container exists.

1. Replace the Python task-code block. Notice the explicit SKU partition key and the source-ID mapping:

    ```python
    # TASK CODE
    product_by_sku = database.get_container_client("productBySku")
    # A client reference doesn't create the container; this read checks it exists.
    product_by_sku.read()
    # ARM container creation doesn't prove that initial data copying has finished.
    wait_for_rows(product_by_sku, "SELECT VALUE COUNT(1) FROM c", [], [295])
    parameters = [{"name": "@sku", "value": SKU}]
    # SKU isn't the source partition key, so this lookup isn't partition-scoped.
    source_query = (
        "SELECT c.id AS sourceId, c.sku, c.name, c.price, c.categoryId FROM c WHERE c.sku = @sku"
    )
    # The GSI generates id; _id preserves the source id for result comparison.
    index_query = (
        "SELECT c._id AS sourceId, c.sku, c.name, c.price, c.categoryId FROM c WHERE c.sku = @sku"
    )
    source_rows, source_charge = measure(product, source_query, parameters)
    if len(source_rows) != 1:
        raise ValueError("Expected one source product for this SKU.")
    # The explicit SKU key routes these requests to one GSI logical partition.
    wait_for_rows(product_by_sku, index_query, parameters, source_rows, partition_key=SKU)
    index_rows, index_charge = measure(product_by_sku, index_query, parameters, partition_key=SKU)
    if index_rows != source_rows:
        raise ValueError("Source and GSI results differ.")
    # Keep the item and policy unchanged to isolate the GSI's added write charge.
    source = business_item(product.read_item(item=PRODUCT_ID, partition_key=CATEGORY_ID))
    print(f"Source lookup: {source_charge:.2f} RU; targeted GSI lookup: {index_charge:.2f} RU")
    print(f"Source replace after GSI: {replace_charge(product, source):.2f} RU")
    ```

1. Run `python measure.py`. The program waits for data, not a Metrics label.

    **Compare:** the two lookup charges are from this run. Compare source replace with **before GSI** from this task; the policy and item are unchanged. Equal lookup charges are valid for this small catalog. The GSI's generated `id` differs; the source ID is in `_id`.

1. Replace the task-code block once more to test source-only writes and automatic propagation:

    ```python
    # TASK CODE
    product_by_sku = database.get_container_client("productBySku")
    # Check that the GSI exists before changing the source price.
    product_by_sku.read()
    source = business_item(product.read_item(item=PRODUCT_ID, partition_key=CATEGORY_ID))
    original_price = source["price"]
    parameters = [{"name": "@sku", "value": SKU}]
    index_query = "SELECT c._id, c.price FROM c WHERE c.sku = @sku"
    try:
        # Write only to the source; Azure Cosmos DB updates the read-only GSI.
        source["price"] = round(original_price + 1, 2)
        product.replace_item(item=PRODUCT_ID, body=source)
        expected = [{"_id": PRODUCT_ID, "price": source["price"]}]
        wait_for_rows(product_by_sku, index_query, parameters, expected, partition_key=SKU)
        print("The source-only price change appeared in the GSI.")
    finally:
        # Restore the original data even if the propagation check fails.
        source["price"] = original_price
        product.replace_item(item=PRODUCT_ID, body=source)
        expected = [{"_id": PRODUCT_ID, "price": original_price}]
        # Verify that the restoration reaches the GSI as well as the source.
        wait_for_rows(product_by_sku, index_query, parameters, expected, partition_key=SKU)
        print("Original price restored in both containers.")
    ```

1. Run `python measure.py`. **Check:** both propagation and restoration complete. The application never writes to the GSI.

## Clean up

Delete only the account created for this exercise:

```powershell
az cosmosdb delete --resource-group $resourceGroup --name $accountName --yes
```

Keep a lab-provided or shared resource group.
