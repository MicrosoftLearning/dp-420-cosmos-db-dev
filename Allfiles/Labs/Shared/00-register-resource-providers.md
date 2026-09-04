---
lab:
  title: 'Register Azure resource providers'
  module: 'Setup'
---

# Register Azure resource providers

A subscription can only create a resource type after the resource provider that owns it is registered. Registration is a one-time step per subscription.

The shared setup script registers `Microsoft.DocumentDB` for you. Follow these steps only if you provision resources by hand, or if a deployment fails with a `MissingSubscriptionRegistration` error.

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

The change feed exercise deploys an Azure Function and reads its logs, so it needs two more providers:

```azurecli
az provider register --namespace Microsoft.Web --wait
az provider register --namespace Microsoft.Insights --wait
```

## Register in the Azure portal

If you prefer the portal, or the CLI reports insufficient permissions:

1. In a web browser, open the [Azure portal](https://portal.azure.com) and sign in.
1. On the **Home** page, select **Subscriptions**, and then select your subscription.
1. In the resource menu, under **Settings**, select **Resource providers**.
1. In the filter box, enter *DocumentDB*.
1. Select the **Microsoft.DocumentDB** row, and then select **Register**.
1. Select **Refresh** until the **Status** column shows **Registered**.

> **Note**: Registering a provider requires the Owner or Contributor role on the subscription. If neither is available to you, ask your subscription administrator to complete this step.
