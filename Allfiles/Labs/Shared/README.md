# Shared lab setup

Environment preparation shared by every DP-420 exercise. Complete these once, then reuse the same Azure Cosmos DB account throughout the course.

## Order

1. [Set up your lab environment](00-setup-local-environment.md) — tools and runtimes
1. [Register Azure resource providers](00-register-resource-providers.md) — only if provisioning by hand or recovering from an error
1. [Create your Azure Cosmos DB account](00-create-cosmos-account.md) — runs `setup.ps1`
1. [Prepare the lab data](00-prepare-lab-data.md) — what each lab profile contains

## Profile per exercise

| Exercise | Profile | Notes |
| :--- | :--- | :--- |
| Explore Azure Cosmos DB for NoSQL | *none* | Creates its own account by hand. That's the learning objective |
| Configure resources, throughput, and consistency | `core` | |
| Connect to Azure Cosmos DB with the SDK | `core` | Mostly uses the local emulator |
| Implement Azure Cosmos DB operations with the SDK | `core` | Enables TTL on `product` as its first step |
| Query data in Azure Cosmos DB for NoSQL | `core` | Needs the seeded `product` container |
| Design a data modeling and partitioning strategy | `modeling` | |
| Process the Azure Cosmos DB change feed | `core` | Region must support container copy jobs |
| Implement AI-assisted development tools | `core` | Also needs a Microsoft Foundry project |

## Design notes

**Key-based authentication is disabled on the account.** Every exercise authenticates with Microsoft Entra ID through `DefaultAzureCredential`, picking up the identity from `az login`. No key or connection string appears anywhere in this course.

**Creating databases and containers is a control-plane operation.** The Cosmos DB data-plane roles grant no permission over databases or containers, only over the items inside them, so `CreateDatabaseIfNotExistsAsync` and `create_container_if_not_exists` return 403 against an Entra-only account. That's why provisioning lives here rather than in exercise code.

**Container copy jobs need the `cosmosdb-preview` CLI extension.** The change feed exercise installs it at the point of use.

## Status

Seed data is validated against the live CosmicWorks dataset: `product` holds 295 items with no missing `categoryId`, and `productMeta` holds 237 items (37 `category`, 200 `tag`) with no missing `type`.

`setup.ps1` has not yet been run end to end against a live subscription. Run `verify.ps1` immediately after the first `setup.ps1` to confirm the data-plane REST path, particularly the encoding of the `Authorization` header for Microsoft Entra ID tokens. `verify.ps1` reports HTTP 401 with a pointer to that header if it's wrong.
