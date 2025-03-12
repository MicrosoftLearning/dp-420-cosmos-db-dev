---
lab:
    title: 'Create lab resource group'
    module: 'Setup'
---

# Create Azure resource group for lab

Before completing this lab, you should create a new [resource group][docs.microsoft.com/azure/azure-resource-manager/management/manage-resource-groups-portal] to place the newly deployed Azure resource into.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. On the **Home** page, select **Resource groups**.

    > &#128161; Alternatively; expand the **&#8801;** menu, select **All Services**, and in the **All** category, select **Resource groups**.

1. Select **+ Create**.

1. In the **Create a resource group** popup, create a new resource group with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Give your resource group a unique name* |
    | **Region** | *Choose any available region* |

1. Wait for the deployment task to complete before continuing with this task.

[docs.microsoft.com/azure/azure-resource-manager/management/manage-resource-groups-portal]: https://docs.microsoft.com/azure/azure-resource-manager/management/manage-resource-groups-portal
