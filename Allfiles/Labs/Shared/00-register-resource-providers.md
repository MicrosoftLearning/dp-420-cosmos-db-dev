---
lab:
  title: 'Register Azure resource providers'
  module: 'Setup'
---

# Register Azure resource providers

A subscription can only create a resource type after the resource provider that owns it is registered. Registration is a one-time step per subscription.

The shared setup script registers `Microsoft.DocumentDB` for you. Follow these steps only if you provision resources by hand, or if a deployment fails with a `MissingSubscriptionRegistration` error.

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

Follow your exercise's instructions for additional services. The shared setup script registers the providers its selected profile needs. The change feed exercise runs its function locally, so it doesn't require a Function App deployment.

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
