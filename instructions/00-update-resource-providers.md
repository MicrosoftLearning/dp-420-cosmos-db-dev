---
lab:
    title: 'Enable resource providers'
    module: 'Setup'
---

# Enable Azure resource providers

There are some resource providers that must be registered in your Azure subscription. Follow these steps to ensure that they're registered.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. On the **Home** page, select **Subscriptions**.

    > &#128161; Alternatively; expand the **&#8801;** menu, select **All Services**, and in the **All** category, select **Subscriptions**.

1. Select your Azure subscription.

    > &#128221; If you have multiple subscriptions, select the one you created by redeeming your Azure Pass.

1. In the blade for your subscription, in the **Settings** section, select **Resource providers**.

1. In the list of resource providers, ensure the following providers are registered:
    - [Microsoft.DocumentDB][docs.microsoft.com/azure/templates/microsoft.documentdb/databaseaccounts]
    - [Microsoft.Insights][docs.microsoft.com/azure/templates/microsoft.insights/components]
    - [Microsoft.KeyVault][docs.microsoft.com/azure/templates/microsoft.keyvault/vaults]
    - [Microsoft.Search][docs.microsoft.com/azure/templates/microsoft.search/searchservices]
    - [Microsoft.Web][docs.microsoft.com/azure/templates/microsoft.web/sites]

    > &#128221; If a provider is not registered, select that provider and then select **Register**.

1. Close your web browser window or tab.

[docs.microsoft.com/azure/templates/microsoft.documentdb/databaseaccounts]: https://docs.microsoft.com/azure/templates/microsoft.documentdb/databaseaccounts
[docs.microsoft.com/azure/templates/microsoft.insights/components]: https://docs.microsoft.com/azure/templates/microsoft.insights/components
[docs.microsoft.com/azure/templates/microsoft.keyvault/vaults]: https://docs.microsoft.com/azure/templates/microsoft.keyvault/vaults
[docs.microsoft.com/azure/templates/microsoft.search/searchservices]: https://docs.microsoft.com/azure/templates/microsoft.search/searchservices
[docs.microsoft.com/azure/templates/microsoft.web/sites]: https://docs.microsoft.com/azure/templates/microsoft.web/sites
