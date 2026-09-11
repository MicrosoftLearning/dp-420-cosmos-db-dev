---
lab:
  title: Secure an account in Python
  module: Module 9 - Secure an Azure Cosmos DB Solution
  description: Secure an Azure Cosmos DB for NoSQL account with Microsoft Entra authentication, a managed identity, scoped data-plane roles, and network access restrictions.
  duration: 45 minutes
  level: 300
  islab: true
  primarytopics:
    - Azure
    - Azure Cosmos DB
    - Azure Portal
---

# Secure an account in Python

Contoso needs evidence that its product reader can't write products and respects network restrictions. You host a client in Azure Container Instances (ACI) with a system-assigned managed identity and test container-scoped access. Your local Azure CLI identity manages resources. Only the hosted identity accesses data.

Key rotation and dynamic data masking aren't part of this exercise.

This exercise takes approximately **45** minutes to complete.

## Before you start

To complete this exercise, you need an [Azure subscription](https://azure.microsoft.com/free/) with permission to create resources and assign roles.

If your lab environment isn't set up yet, follow [Set up your lab environment](https://github.com/MicrosoftLearning/dp-420-cosmos-db-dev/blob/main/Allfiles/Labs/Shared/00-setup-local-environment.md) to install Visual Studio Code, Git, the Azure CLI, and PowerShell 7.

You don't need a local Python installation. The container image supplies the runtime, and every line of application code in this exercise runs inside that container.

This exercise also requires:

- Azure **Contributor** access to the resources in the resource group you use. Cosmos DB native role assignments are resource-provider operations rather than generic Azure role assignments, so a data-plane role isn't enough to make them.
- Registered `Microsoft.DocumentDB` and `Microsoft.ContainerInstance` resource providers, or permission to register them. Registration requires each provider's `/register/action` permission at subscription scope. Your subscription administrator or lab provider can register missing providers when you don't have this permission. See [Azure resource providers and types](/azure/azure-resource-manager/management/resource-providers-and-types).
- A region, such as `eastus`, that supports Azure Cosmos DB serverless and Linux [Azure Container Instances](/azure/container-instances/container-instances-region-availability), with quota for 2 CPUs and 4 GB of memory. The container needs outbound access to Azure Cosmos DB, the managed identity endpoint, GitHub, and package repositories.

Charges include ACI uptime and Azure Cosmos DB serverless request units (RUs) and storage. Complete the cleanup task even after a failure.

## Set up your Azure Cosmos DB resources

This exercise creates its own Azure Cosmos DB account and deletes it at the end, so it doesn't use the shared account from the rest of this learning path. Later steps switch public network access off and back on, which would interrupt every other exercise running against a shared account.

> &#9888; Use only the account this script creates for this exercise. The network test deliberately blocks all public data access to that account. Never point this exercise at a shared training or production account.

1. Start **Visual Studio Code**.

1. If you don't have the lab code yet, clone the repository for DP-420: open the command palette with Ctrl+Shift+P, run Git: Clone, and enter the following URL. Choose a local folder when prompted. Otherwise, open the folder from your previous clone.

    ```
    https://github.com/microsoftlearning/dp-420-cosmos-db-dev
    ```

1. Once the repository is cloned, open that local folder in **Visual Studio Code**.

1. In the **Explorer** pane, browse to the **Allfiles/Labs/Shared** folder.

1. Open the context menu for the folder and select **Open in Integrated Terminal**. If the terminal isn't PowerShell, select the dropdown beside the **+** in the terminal toolbar and choose **PowerShell**. Keep this **local PowerShell** session open for the whole exercise: its variables stay available after you exit the container shell.

1. Sign in to the Azure CLI and confirm the subscription you're working in. Follow the sign-in prompts for your environment. Select the intended subscription if prompted.

    ```azurecli
    az login
    az account show --query '{Subscription:name,Id:id}' --output table
    ```

1. Set variables for the resource group and region. Use `ResourceGroup1`, or the group supplied by your lab if its name differs.

    ```powershell
    $resourceGroup = "ResourceGroup1"
    $location = "eastus"
    ```

1. Run the setup script.

    ```powershell
    ./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab09 -LabProfile security
    ```

    Azure Cosmos DB account names have to be globally unique, so the script builds one for you by adding six random characters to the prefix, giving a name like `dp420lab09a7f3k9`.

1. Wait for the script to finish. The whole script takes 5-10 minutes to run.

1. Record the **Account name** and **Account endpoint** values the script prints. You need both throughout this exercise, and the endpoint looks like `https://<your-account-name>.documents.azure.com:443/`.

1. Set variables for the account and the container group so the commands in this exercise can use them.

    ```powershell
    $account = "<your-account-name>"
    $groupName = "security-client"
    $endpoint = az cosmosdb show --resource-group $resourceGroup --name $account `
        --query documentEndpoint --output tsv
    ```

1. Confirm the security baseline. Expect local authentication disabled and public network access enabled.

    ```azurecli
    az cosmosdb show --resource-group $resourceGroup --name $account `
        --query '{LocalAuthDisabled:disableLocalAuth,PublicAccess:publicNetworkAccess}' --output table
    ```

The script creates the following resources:

| Resource | Configuration |
| :--- | :--- |
| Azure Cosmos DB account | API for NoSQL, serverless, with key-based authentication disabled and public network access enabled |
| `cosmicworks` database | Holds the container this exercise uses |
| `product` container | Partitioned on `/categoryId`, serverless, and empty. Loading it is the first thing you prove the hosted identity can do |

Because key-based authentication is disabled, no key or connection string appears anywhere in this exercise. No command retrieves an account key.

The `security` profile deliberately grants **no** data-plane role to your signed-in identity. The tests use the hosted managed identity. Assigning a data-plane role to your local Azure CLI identity doesn't change the hosted identity's permissions.

## Task 1: Write the managed identity client

Prepare source locally before creating ACI. The client downloads 295 CosmicWorks v4 products once into `products.json` inside the container, retaining their full schema. All tests reuse the cached first record's actual `id` and `categoryId`. A different count or invalid structure stops the client.

The `seed` mode upserts the dataset. The `read` mode performs a point read. The `check` mode reads, then attempts replacement with the original downloaded values. Only a replacement 403 after read success counts as expected denial. Unexpected write success returns failure without changing business values, although server-maintained metadata can change.

1. Create a local working folder in **local PowerShell**. Keep this directory separate from the container's working directory.

    ```powershell
    $workFolder = Join-Path $HOME 'dp420-security'
    New-Item -ItemType Directory -Path $workFolder -Force | Out-Null
    Set-Location $workFolder
    ```

1. Create `app.py` in Visual Studio Code with the following complete program. Preserve Python indentation. Output contains statuses, not tokens, products, or full exception messages. Python uses Gateway mode. The outer handler also covers client initialization, because initialization can contact the account. The context manager closes the client, and `finally` closes the credential.

    ```python
    import json
    import os
    import sys
    from pathlib import Path
    from urllib.request import urlopen

    from azure.cosmos import CosmosClient
    from azure.cosmos.exceptions import CosmosHttpResponseError
    from azure.identity import ManagedIdentityCredential


    def main():
        if len(sys.argv) != 2 or sys.argv[1] not in {"seed", "read", "check"}:
            print("Usage: seed | read | check")
            return 2

        mode = sys.argv[1]
        credential = None
        try:
            endpoint = os.environ.get("COSMOS_ENDPOINT")
            if not endpoint or not endpoint.strip():
                print("COSMOS_ENDPOINT is required.")
                return 2

            source_url = "https://raw.githubusercontent.com/AzureCosmosDB/CosmicWorks/main/data/database-v4/product"
            cache_file = Path("products.json")
            if not cache_file.exists():
                with urlopen(source_url, timeout=60) as response:
                    cache_file.write_bytes(response.read())

            products = json.loads(cache_file.read_text(encoding="utf-8"))
            if not isinstance(products, list) or len(products) != 295 or any(
                not isinstance(product, dict)
                or not isinstance(product.get("id"), str)
                or not isinstance(product.get("categoryId"), str)
                for product in products
            ):
                raise ValueError("Invalid dataset")

            first_product = products[0]
            product_id = first_product["id"]
            category_id = first_product["categoryId"]
            credential = ManagedIdentityCredential()
            with CosmosClient(endpoint, credential=credential) as client:
                database = client.get_database_client("cosmicworks")
                container = database.get_container_client("product")

                if mode == "seed":
                    for product in products:
                        container.upsert_item(body=product)
                    print(f"Seed succeeded: {len(products)} items.")
                    return 0

                container.read_item(item=product_id, partition_key=category_id)
                print("Read succeeded.")
                if mode == "read":
                    return 0

                try:
                    container.replace_item(item=product_id, body=first_product)
                    print("UNEXPECTED: Write succeeded.")
                    return 1
                except CosmosHttpResponseError as exception:
                    if exception.status_code != 403:
                        raise
                    print("Write denied (403). Expected.")
                    return 0
        except CosmosHttpResponseError as exception:
            if exception.status_code == 403:
                print("Seed denied (403)." if mode == "seed" else "Read denied (403).")
                return 3
            print(f"Unexpected Cosmos status ({exception.status_code}).")
            return 1
        except Exception as exception:
            print(f"Unexpected failure ({type(exception).__name__}).")
            return 1
        finally:
            if credential is not None:
                credential.close()


    if __name__ == "__main__":
        sys.exit(main())
    ```

1. Set the image and source filename in **local PowerShell**. Don't run the program locally: only the container exposes its managed identity.

    ```powershell
    $image = 'python:3.12-slim-bookworm'
    $sourceFile = 'app.py'
    ```

## Task 2: Host the client and load products

ACI supplies the Linux process with a managed identity endpoint. Temporary Data Contributor access at product-container scope permits loading. This exercise simplification differs from production, where a separate loader identity keeps the application read-only.

### Create the host identity

1. Encode the source file in **local PowerShell**. Base64 transfers text through an environment variable. It isn't encryption, and this source contains no secrets.

    ```powershell
    $sourceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $sourceFile)))
    ```

1. Create ACI with a system-assigned identity and an idle process for repeated sessions. Omit identity `--scope` and `--role`: no Azure management grant is needed. Public IP, DNS label, and port options remain unset.

    ```azurecli
    az container create --resource-group $resourceGroup --name $groupName `
        --location $location --image $image --os-type Linux --cpu 2 --memory 4 `
        --assign-identity --restart-policy Never --command-line 'tail -f /dev/null' `
        --environment-variables "COSMOS_ENDPOINT=$endpoint" "SOURCE_BASE64=$sourceBase64"
    ```

1. Check for `Running` and capture the principal object ID. Continue only with a nonempty ID. Investigate provisioning or capacity errors otherwise.

    ```powershell
    az container show --resource-group $resourceGroup --name $groupName `
        --query 'containers[0].instanceView.currentState.state' --output tsv
    $principalId = az container show --resource-group $resourceGroup --name $groupName `
        --query identity.principalId --output tsv
    $principalId
    ```

1. Grant temporary native Data Contributor. Retain the assignment ID for exact deletion later. Verify the returned principal, role ending in `0002`, and product-container scope.

    ```powershell
    $scope = '/dbs/cosmicworks/colls/product'
    $seedAssignment = [Guid]::NewGuid().ToString()
    az cosmosdb sql role assignment create --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $seedAssignment `
        --principal-id $principalId --scope $scope `
        --role-definition-id '00000000-0000-0000-0000-000000000002'
    ```

### Initialize the container workspace

1. Enter **container Bash** from **local PowerShell**. ACI exec starts one shell command; enter subsequent commands at the Bash prompt.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $groupName --exec-command /bin/bash
    ```

1. Initialize the project in **container Bash**. Decode the source and install unpinned supported packages. Continue only after installation completes successfully.

    ```bash
    mkdir -p /work/security
    cd /work/security
    printenv SOURCE_BASE64 | base64 --decode > app.py
    python -m venv .venv
    .venv/bin/python -m pip install azure-cosmos azure-identity
    ```

1. Load the products in **container Bash**. Expect `Seed succeeded: 295 items.` and exit code `0`. For a 403, check the recorded principal and scope locally, allow propagation, and retry. Don't broaden the grant. A retry uses the cache and upserts the same products.

    ```bash
    .venv/bin/python app.py seed
    echo $?
    ```

1. Return to **local PowerShell**. Exiting Bash leaves the idle container running and preserves your PowerShell variables.

    ```bash
    exit
    ```

Reattach to the same running container without restarting it. Container files aren't durable: restart or replacement can lose the cache and dependencies. After such a loss, repeat initialization and establish a fresh baseline.

## Task 3: Enforce and test read-only access

Adding Reader doesn't cancel Contributor. Remove the temporary grant, then test with the principal, data, and network unchanged to isolate authorization.

1. Add native Data Reader in **local PowerShell**, at the same scope. Data Reader is the application's intended steady-state permission.

    ```powershell
    $readerAssignment = [Guid]::NewGuid().ToString()
    az cosmosdb sql role assignment create --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $readerAssignment `
        --principal-id $principalId --scope $scope `
        --role-definition-id '00000000-0000-0000-0000-000000000001'
    ```

1. Delete the exact temporary seed assignment in **local PowerShell**.

    ```azurecli
    az cosmosdb sql role assignment delete --resource-group $resourceGroup `
        --account-name $account --role-assignment-id $seedAssignment --yes
    ```

1. Inspect all native assignments for the principal in **local PowerShell**. Expect only Reader, ending in `0001`, at the product scope. Don't accept a remaining Contributor or broader assignment.

    ```azurecli
    az cosmosdb sql role assignment list --resource-group $resourceGroup --account-name $account `
        --query "[?principalId=='$principalId'].{Role:roleDefinitionId,Scope:scope,Assignment:id}" --output table
    ```

1. To test the hosted identity, not your CLI identity, reenter **container Bash** from **local PowerShell**.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $groupName --exec-command /bin/bash
    ```

1. Run the check in **container Bash**. Each invocation starts a new process whose read and replacement share one client and identity.

    ```bash
    cd /work/security
    .venv/bin/python app.py check
    echo $?
    ```

    Expect this output. Initial read denial prevents the write and fails the test. If writing succeeds, stop, verify assignment removal, allow propagation, and rerun a new process. Continue only with both expected results.

    ```output
    Read succeeded.
    Write denied (403). Expected.
    0
    ```

1. Return to **local PowerShell** before changing account settings.

    ```bash
    exit
    ```

## Task 4: Block and restore the public network path

Change only public-network access. Keep the role, principal, container, cache, and item address unchanged. This change tests a public-network restriction, not an IP allowlist or private endpoint deployment.

> &#9888; This isolated account has no private endpoint. Disabling public access creates a complete data-access outage for this exercise, not proof of working private connectivity. Restore the public baseline only on this disposable account.

### Verify the blocked read

1. Disable public access in **local PowerShell**. Don't change any permissions or reload data.

    ```azurecli
    az cosmosdb update --resource-group $resourceGroup --name $account --public-network-access DISABLED
    ```

1. Inspect the setting in **local PowerShell**. Expect `Disabled`. This management-plane request still works and doesn't demonstrate data access.

    ```azurecli
    az cosmosdb show --resource-group $resourceGroup --name $account --query publicNetworkAccess --output tsv
    ```

1. To reuse the same network source and managed identity, enter **container Bash** from **local PowerShell**.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $groupName --exec-command /bin/bash
    ```

1. Run the point read in **container Bash**. Expect `Read denied (403).` and intentional exit code `3`. Allow up to 15 minutes for network propagation. Don't accept successful reads as isolation: check the setting and retry. Other errors are inconclusive.

    ```bash
    cd /work/security
    .venv/bin/python app.py read
    echo $?
    ```

1. To restore the baseline, return to **local PowerShell**, including if the blocked test remains inconclusive.

    ```bash
    exit
    ```

### Verify restored access and retained restrictions

1. Restore public access in **local PowerShell**. The final command needs to show `Enabled`. Keep Reader and key-based authentication settings unchanged.

    ```azurecli
    az cosmosdb update --resource-group $resourceGroup --name $account --public-network-access ENABLED
    az cosmosdb show --resource-group $resourceGroup --name $account --query publicNetworkAccess --output tsv
    ```

1. Reenter **container Bash** from **local PowerShell** for the final comparison.

    ```azurecli
    az container exec --resource-group $resourceGroup --name $groupName --exec-command /bin/bash
    ```

1. Repeat the read and authorization check in **container Bash**. Expect read success, then the earlier read-success and write-denial pair, each with exit code `0`. Retry after propagation as needed. Don't accept unexpected results or change roles to make reads succeed.

    ```bash
    cd /work/security
    .venv/bin/python app.py read
    echo $?
    .venv/bin/python app.py check
    echo $?
    ```

1. Return to **local PowerShell** for cleanup. Python uses its virtual environment's interpreter directly, so no environment deactivation is necessary.

    ```bash
    exit
    ```

Record observations, timestamps, principal, and scope against this table, without credentials or product values. Operations gets outage evidence, while security reviewers check that restored connectivity doesn't restore writes. All comparisons must match before you record a pass.

| Stage | Public access | Native role | Expected read | Expected replacement |
| --- | --- | --- | --- | --- |
| Before blocking | Enabled | Data Reader | Succeeds | Denied, 403 |
| Blocked | Disabled | Same Data Reader | Denied, 403 | Not attempted |
| Restored | Enabled | Same Data Reader | Succeeds | Denied, 403 |

Learn more about [managed identities in ACI](/azure/container-instances/container-instances-managed-identity), [Cosmos DB data-plane roles](/azure/cosmos-db/reference-data-plane-security), and [account network restrictions](/azure/cosmos-db/how-to-configure-firewall).

## Clean up resources

Remove this exercise's disposable resources when you finish, even after a partial or failed run. Run the group-deletion steps only if you created the group and it contains only this exercise's resources. If your lab provided `ResourceGroup1`, keep the group and use the individual account and container-group deletion commands instead.

1. Inspect the subscription, group, and resources in **local PowerShell**. Resolve any unexpected resource before deletion.

    ```azurecli
    az account show --query '{Subscription:name,Id:id}' --output table
    az group show --name $resourceGroup --query '{Name:name,Id:id}' --output json
    az resource list --resource-group $resourceGroup --query '[].{Name:name,Type:type}' --output table
    ```

1. Delete the inspected group in **local PowerShell**. Deleting the group permanently removes the account, its data, and the ACI host. Review the interactive confirmation before approving.

    ```azurecli
    az group delete --name $resourceGroup
    ```

1. Verify deletion in **local PowerShell**. Expect `false`; otherwise investigate deletion status. Whole-group cleanup includes resources from incomplete setup.

    ```azurecli
    az group exists --name $resourceGroup
    ```

If your lab provided the resource group, or the group holds other resources, delete only this exercise's account and container group:

```azurecli
az cosmosdb delete --name $account --resource-group $resourceGroup --yes
az container delete --name $groupName --resource-group $resourceGroup --yes
```

This exercise demonstrates three distinct boundaries: hosted identity, scoped data permissions, and network access. The paired positive and negative tests provide evidence for those operations without claiming production-wide security.
