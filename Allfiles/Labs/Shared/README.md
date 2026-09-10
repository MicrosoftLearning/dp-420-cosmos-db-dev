# Shared lab setup

Use these guides to prepare for the DP-420 exercises. Follow your exercise's setup steps to choose a profile and determine whether to reuse an account or create a disposable one.

## Order

1. [Set up your lab environment](00-setup-local-environment.md): tools and runtimes.
1. [Register Azure resource providers](00-register-resource-providers.md): only if provisioning by hand or recovering from an error.
1. [Create your Azure Cosmos DB account](00-create-cosmos-account.md): run `setup.ps1` with the options in your exercise.
1. [Prepare the lab data](00-prepare-lab-data.md): check what your lab profile contains.

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
| Implement AI-assisted development tools | `aitools` | Automatic search configuration; add `-EnableFoundry` for embedding and chat deployments |
| Secure an Azure Cosmos DB account | `security` | Disposable account, own resource group. Also needs Azure Container Instances quota |
| Configure backup and restore | `backup` | Disposable account, own resource group. Continuous backup at `Continuous7Days` |
| Design multi-region availability and failover | `multiregion` | Disposable account, own resource group. Two regions |
| Design and optimize an indexing strategy | `indexing` | Disposable account, own resource group. Continuous backup at `Continuous7Days` |
| Analyze and tune query performance | `core` | Needs the seeded `product` container |
| Monitor and troubleshoot Azure Cosmos DB | `monitoring` | Disposable account, own resource group. `product` at 400 RU/s manual |
| Manage Azure Cosmos DB at scale with fleets | `fleet` | **Two** disposable accounts, own resource group. Identical single-region configuration |
| Implement full-text and vector search | `search` | Add `-EnableFoundry -EmbeddingOnly`; empty `productSearch` container with full-text and vector policies |
| Implement hybrid search and optimize retrieval | `search` | Add `-EnableFoundry -EmbeddingOnly`; same search topology |
| Build RAG applications | `search` | Add `-EnableFoundry` for embedding and chat deployments |
| Design and implement agent memory stores | `agentmemory` | Add `-EnableFoundry`; empty `conversation` and `memory` containers, vector and delete-by-partition-key capabilities |
| Implement operational analytics with Fabric | `mirroring` | Continuous7Days, single-region writes, all-network public access; Fabric capacity and workspace are separate prerequisites |

## Check regional availability

Normal setup checks the required resource provider registrations and registers missing providers before checking service availability. It then checks the regions for your selected profile before creating a resource group or creating or changing lab resources. Use the intended subscription for your `az login` session. The checks include:

- Cosmos DB regional status and your subscription's regional access for new accounts. On reruns, setup checks the existing account's actual regions.
- Both Cosmos DB regions for `multiregion`, and the documented container-copy regions for the shared `core` account.
- Container Instances for `security`, Log Analytics workspaces for `monitoring`, and fleets and storage accounts for `fleet`, using each resource provider's region list.
- With `-EnableFoundry`, the exact model versions and deployment types in `-FoundryLocation`, supported capacity values, reported deployable capacity, and remaining model quota. Matching existing model deployments don't require more quota.

To check your choices without provisioning, add `-PreflightOnly` to the setup command from your exercise. This mode checks provider registration but doesn't change it. If a required provider isn't registered, follow [Register Azure resource providers](00-register-resource-providers.md) before rerunning the check. For example, with the resource group and region variables from the retrieval-augmented generation (RAG) exercise:

```powershell
./setup.ps1 -ResourceGroup $resourceGroup -Location $location -NamePrefix dp420lab18 -LabProfile search -EnableFoundry -FoundryLocation eastus -PreflightOnly
```

Remove `-PreflightOnly` to run setup. Keep the other options the same, including any account name or model overrides. Setup repeats the checks on each run. If a check fails or Azure doesn't return enough information, setup stops before provisioning. Use the error message to correct `-Location`, `-SecondaryLocation`, or `-FoundryLocation`, or resolve the quota or access issue. Setup doesn't choose a different region or model for you.

These checks don't reserve capacity or guarantee deployment success. Azure Policy, permissions, service-specific restrictions, and changing capacity can still affect deployment. Follow the service-specific prerequisites in your exercise. Fabric capacity and workspace access also remain separate prerequisites; the script doesn't verify them.

## Optional Foundry deployment

`setup.ps1 -EnableFoundry` deploys the separate `foundry.bicep` template in the same resource group as the lab. It creates a Microsoft Foundry resource and a project named `dp420`, disables key authentication, and grants the signed-in user **Foundry User**. It deploys `text-embedding-3-small` version `1` on **Standard** and `gpt-5.4-mini` version `2026-03-17` on **GlobalStandard**, each with 30 model-specific capacity units. Both deployment types use token billing, not provisioned model capacity.

For modules 16 and 17, add `-EmbeddingOnly` to omit chat. Modules 8, 18, and 19 use both models. Without `-EnableFoundry`, setup makes no Foundry requests and preserves the existing Cosmos-only workflow. Azure Developer CLI (`azd`) isn't required.

| Parameter | Default and purpose |
| :--- | :--- |
| `-EnableFoundry` | Off. Opt in to model provisioning |
| `-EmbeddingOnly` | Off. Skip chat when used with `-EnableFoundry` |
| `-FoundryLocation` | `eastus`. Independent of the Cosmos DB `-Location` |
| `-FoundryAccountName` | Cosmos DB account name followed by `-ai`. Stable across retries |
| `-FoundryProjectName` | `dp420` |
| `-EmbeddingModel`, `-EmbeddingModelVersion` | `text-embedding-3-small`, `1` |
| `-ChatModel`, `-ChatModelVersion` | `gpt-5.4-mini`, `2026-03-17` |
| `-EmbeddingDeploymentSku`, `-ChatDeploymentSku` | `Standard`, `GlobalStandard`. Only pay-per-token deployment types are accepted |
| `-EmbeddingCapacity`, `-ChatCapacity` | `30` each. New deployments only; existing capacity is preserved |

Keep the same Foundry options on reruns. Existing matching accounts, projects, model deployments, and role assignments are reused rather than reset. An incompatible model/version, account kind, region, or authentication setting stops setup with a message. Existing container policies also remain unchanged.

If your Foundry resource contains an older chat deployment under a different name, rerunning setup adds `gpt-5.4-mini` without removing the older deployment. Update application configuration to the new deployment name and test it before removing any unused deployment. Check the [model retirement schedule](https://learn.microsoft.com/azure/foundry/openai/concepts/model-retirement-schedule) before selecting a different model.

Model availability and quota vary by subscription and region. A deployment failure doesn't require deleting the Cosmos DB account. Resolve quota, permissions, or model availability, then rerun against the recorded `-AccountName`. If a new Foundry region is needed, use a different `-FoundryAccountName` and pass that name to verification as well. Delete any unused resource only after checking its ownership and dependencies.

Setup prints the OpenAI endpoint, project endpoint, and model deployment names, and saves them in `logs/foundry-<cosmos-account-name>.json`. This file contains no keys or tokens. The direct retrieval-augmented generation (RAG) and memory examples append `/openai/v1/` to **OpenAiEndpoint** and use the OpenAI SDK with Microsoft Entra ID. The pinned Agent Memory Toolkit takes the resource endpoint without that suffix. The project endpoint is a different URL.

The direct chat examples use `reasoning_effort="none"`, omit sampling parameters such as `temperature`, and set `max_completion_tokens`. C# uses the corresponding `ReasoningEffortLevel` and `MaxOutputTokenCount` options. These choices target short catalog responses; changing to a different model requires checking its [supported parameters](https://learn.microsoft.com/azure/foundry/openai/how-to/reasoning).

The lab vector policies use 1,536 dimensions. `text-embedding-3-small` produces that length by default. Selecting `text-embedding-3-large` requires requesting `dimensions=1536` in application code. Model provisioning doesn't generate document embeddings: the exercise code creates them from your data.

Add `-EnableFoundry` to `verify.ps1` to check the account, project, model deployment states and versions, and user role. Add `-EmbeddingOnly` for modules 16 and 17. Pass matching model-name/version overrides if you changed the setup defaults. These are management-plane checks; inference and role propagation are verified when the exercise calls the models.

## Fabric mirroring setup

Module 20 uses `-LabProfile mirroring` without `-EnableFoundry`. The profile creates a keyless Cosmos DB account with continuous backup and seeds the `product` and `customer` containers. It doesn't create Fabric capacity, a workspace, or a mirrored database.

Run `verify.ps1` with the mirroring profile before the Fabric tasks. The lab uses public access for all networks; setup and verification reject restricted networking and multi-region writes without changing existing accounts. Private-network mirroring requires separate Network ACL Bypass configuration.

The exercise deliberately creates the custom `readAnalytics` role as a learning task. After that task, run verification again with `-CheckMirroringPermissions`. This verification checks the signed-in user's direct account-scoped `readMetadata` and `readAnalytics` grants. Fabric connection and replication remain portal checks. Existing accounts can support migration from periodic to continuous backup, but this script doesn't perform that migration.

## Shared account or disposable account

The `core` profile supplies the account reused by the core exercises. Keep its resource group, account name, and endpoint. Before reuse, run `verify.ps1` with `-LabProfile core` against that named account and confirm the catalog counts in Data Explorer: 295 products and 237 product metadata items. The two-item account from the first portal exercise isn't this baseline.

When adding missing core resources to an existing lab account, pass `-AccountName` explicitly. The module-specific name prefix selects only accounts with that prefix, not every course account. Setup upserts seed records but doesn't delete extra items or reset existing container policies. Resolve verification failures and restore the exercise's stated starting configuration before continuing; don't delete or reset data automatically.

The `modeling` profile uses a separate account in `dp420-modeling`. Its cleanup runs immediately after the exercise, so never put it in the core account's resource group.

The `security`, `backup`, `multiregion`, `indexing`, `monitoring`, `fleet`, `search`, `agentmemory`, `aitools`, and `mirroring` profiles create **disposable** accounts instead, and their exercises delete them when they finish. These exercises change account settings or data, so use the dedicated account specified in your exercise. Use a dedicated resource group when the lab doesn't provide one. Keep lab-provided and shared groups during cleanup, removing only the disposable resources you created.

## Setup details

**Key-based authentication is disabled on the account.** Every exercise authenticates with Microsoft Entra ID through `DefaultAzureCredential`, picking up the identity from `az login`. No key or connection string appears anywhere in this course.

**Creating databases and containers is a control-plane operation.** The Cosmos DB data-plane roles grant no permission over databases or containers, only over the items inside them, so `CreateDatabaseIfNotExistsAsync` and `create_container_if_not_exists` return 403 against an Entra-only account. That's why provisioning lives here rather than in exercise code.

**Container copy jobs need the `cosmosdb-preview` CLI extension.** The change feed exercise installs it at the point of use.

**The `security` profile grants no data-plane role to the signed-in user.** Watching a hosted managed identity gain, then lose, write access is what that exercise measures, so handing your own identity account-wide access up front would hide the result. It also registers `Microsoft.ContainerInstance` alongside `Microsoft.DocumentDB`.

## Verify your setup

For `search`, `agentmemory`, and `aitools`, run the normal setup command without `-AccountOnly`. Setup enables the required account capabilities and creates the containers with vector and English full-text policies and indexes. If Azure reports that vector activation is pending, setup retries the missing containers for up to 15 minutes. Other errors stop the run. These profiles don't require manual full-text enrollment in the portal.

To resume an interrupted run, use the recorded `-AccountName` with the same resource group, profile, and Foundry options. Existing containers remain unchanged. Older commands with `-AccountOnly` or `-SearchFeaturesReady` remain accepted, but neither switch is required. `-AccountOnly` intentionally stops before container setup. Wait for **Setup complete** before running verification.

The `core` profile loads 295 items into `product` and 237 into `productMeta` (37 `category`, 200 `tag`). Check the counts in Data Explorer before reusing the account.

Run `verify.ps1` after setup to check the Cosmos DB resources and authenticated data access. Include `-EnableFoundry` when setup provisions model resources. Verification reports HTTP 401 for a rejected Cosmos DB token; Foundry inference can still fail while a new role assignment propagates.

`verify.ps1` accepts the same `-LabProfile` values as `setup.ps1` and checks the resources and role assignments for that profile. Use the same resource group, account name, and profile you used for setup. Follow your exercise's verification steps and resolve any failed checks before continuing. The `fleet` profile creates two accounts, so run verification once per account.
