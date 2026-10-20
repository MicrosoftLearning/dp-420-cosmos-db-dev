---
lab:
  title: 'Register Azure resource providers'
  module: 'Setup'
---

# Register Azure resource providers

A subscription can only create a resource type after the resource provider that owns it is registered. Registration is a one-time step per subscription.

Normal setup registers the providers its selected profile needs before checking service availability. With `-EnableFoundry`, it also registers `Microsoft.CognitiveServices`. The `-PreflightOnly` mode checks registration without changing it. Follow these steps if you provision resources by hand, if check-only mode reports an unregistered provider, or if a deployment fails with a `MissingSubscriptionRegistration` error.

Before registering a provider, [sign in to Azure and select the subscription](00-setup-local-environment.md#sign-in-to-azure) you use for the exercise.

## Register with the Azure CLI

Registration takes a minute or two. The `--wait` flag holds the command open until it finishes.

```azurecli
az provider register --namespace Microsoft.DocumentDB --wait
```

Confirm the result:

```azurecli
az provider show --namespace Microsoft.DocumentDB --query registrationState --output tsv
```

The command returns `Registered`.

## Register additional providers

The shared [setup script](setup.ps1) registers the following providers based on the selected profile and switches. The same registrations apply to the Python and C# exercises.

| Provider | Required by | Purpose |
| :--- | :--- | :--- |
| `Microsoft.DocumentDB` | All profiles | Azure Cosmos DB accounts, databases, and containers |
| `Microsoft.ContainerInstance` | `security` profile | The hosted container used to access Azure Cosmos DB with a managed identity |
| `Microsoft.Insights` | `monitoring` and `fleet` profiles | Azure Monitor metrics, diagnostic settings, and alert rules |
| `Microsoft.OperationalInsights` | `monitoring` profile | Log Analytics workspaces |
| `Microsoft.Storage` | `fleet` profile | The Data Lake Storage Gen2 destination for fleet analytics |
| `Microsoft.CognitiveServices` | Any profile with `-EnableFoundry` | Foundry resources, projects, and model deployments |

Normal setup handles these registrations automatically. For manual registration or check-only mode, run only the additional commands that apply to your exercise:

```azurecli
az provider register --namespace Microsoft.ContainerInstance --wait
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.CognitiveServices --wait
```

Use the `az provider show` command from the previous section with each provider's namespace to confirm registration. The change feed exercise runs its function locally, so it doesn't require a Function App deployment.

If an error names another unregistered provider, replace `Microsoft.DocumentDB` in the register and show commands with that provider's namespace. Confirm registration, then rerun the failed step.

## Register in the Azure portal

You can also register a provider in the portal. The same subscription permissions are required:

1. In a web browser, open the [Azure portal](https://portal.azure.com) and sign in.
1. On the **Home** page, select **Subscriptions**, and then select your subscription.
1. In the resource menu, under **Settings**, select **Resource providers**.
1. In the filter box, enter *DocumentDB*.
1. Select the **Microsoft.DocumentDB** row, and then select **Register**.
1. Select **Refresh** until the **Status** column shows **Registered**.

> **Note**: If you don't have permission to register a provider, ask your lab or subscription administrator to complete this step. Switching from the CLI to the portal doesn't change your permissions.
