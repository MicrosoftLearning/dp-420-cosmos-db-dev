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
| Secure an Azure Cosmos DB account | `security` | Disposable account, own resource group. Also needs Azure Container Instances quota |
| Configure backup and restore | `backup` | Disposable account, own resource group. Continuous backup at `Continuous7Days` |
| Design multi-region availability and failover | `multiregion` | Disposable account, own resource group. Two regions |
| Design and optimize an indexing strategy | `indexing` | Disposable account, own resource group. Continuous backup at `Continuous7Days` |
| Analyze and tune query performance | `core` | Needs the seeded `product` container |
| Monitor and troubleshoot Azure Cosmos DB | `monitoring` | Disposable account, own resource group. `product` at 400 RU/s manual |
| Manage Azure Cosmos DB at scale with fleets | `fleet` | **Two** disposable accounts, own resource group. Identical single-region configuration |

## Shared account or disposable account

The `core` and `modeling` profiles target the **one account** the course reuses from exercise to exercise. Run setup once, keep the endpoint, and delete the resource group at the end of the course.

The `security`, `backup`, `multiregion`, `indexing`, `monitoring`, and `fleet` profiles create **disposable** accounts instead, and their exercises delete them when they finish. Each needs an account setting or an account-level change the shared account can't carry: the security exercise switches public network access off and back on, continuous backup can only be chosen when an account is created, the multi-region exercise takes a region offline, the monitoring exercise attaches a diagnostic setting that has to be removed before its target resource is deleted, and the fleets exercise needs two accounts with matching configurations to enroll in one fleetspace. Give each of those runs a resource group of its own, so the cleanup step can delete the group without taking the shared account with it.

## Design notes

**Key-based authentication is disabled on the account.** Every exercise authenticates with Microsoft Entra ID through `DefaultAzureCredential`, picking up the identity from `az login`. No key or connection string appears anywhere in this course.

**Creating databases and containers is a control-plane operation.** The Cosmos DB data-plane roles grant no permission over databases or containers, only over the items inside them, so `CreateDatabaseIfNotExistsAsync` and `create_container_if_not_exists` return 403 against an Entra-only account. That's why provisioning lives here rather than in exercise code.

**Container copy jobs need the `cosmosdb-preview` CLI extension.** The change feed exercise installs it at the point of use.

**The `security` profile grants no data-plane role to the signed-in user.** Watching a hosted managed identity gain, then lose, write access is what that exercise measures, so handing your own identity account-wide access up front would hide the result. It also registers `Microsoft.ContainerInstance` alongside `Microsoft.DocumentDB`.

## Status

Seed data is validated against the live CosmicWorks dataset: `product` holds 295 items with no missing `categoryId`, and `productMeta` holds 237 items (37 `category`, 200 `tag`) with no missing `type`.

`setup.ps1` has not yet been run end to end against a live subscription. Run `verify.ps1` immediately after the first `setup.ps1` to confirm the data-plane REST path, particularly the encoding of the `Authorization` header for Microsoft Entra ID tokens. `verify.ps1` reports HTTP 401 with a pointer to that header if it's wrong.

`verify.ps1` accepts the same `-LabProfile` values as `setup.ps1` and checks what each profile actually provisions: the account's capacity mode, backup policy and tier, region count, and public network access, the partition key and throughput of every container, and whether the signed-in user should hold a data-plane role. Pass the profile you set up with, for example `./verify.ps1 -ResourceGroup dp420-monitoring -AccountName <account> -LabProfile monitoring`. The `fleet` profile creates two accounts, so run it once per account. It fails on startup if `setup.ps1` gains a profile it doesn't know about.
