---
lab:
  title: 'Set up your lab environment'
  module: 'Setup'
---

# Set up your lab environment

Use this guide to install the tools your exercise requires. If your lab environment already provides a tool, check its version instead of installing it again.

> **Note**: These instructions target a Windows 11 computer. You can also use Linux or macOS, though you might need to adapt some steps. Because local configurations vary widely, the course team can't support issues you encounter in your own environment.

## Install the core tools

Install these for exercises that use the shared setup script.

| Tool | Notes |
| :--- | :--- |
| [Visual Studio Code](https://code.visualstudio.com/download) | Use the default installer options. |
| [Git](https://git-scm.com/downloads) | Use the default installer options. |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Version 2.61 or later. |
| [PowerShell 7](https://github.com/powershell/powershell/releases/latest) | Needed to run the shared setup script. |

Then install the Visual Studio Code extensions for the language you plan to use:

- **C#**: [C# Dev Kit](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csdevkit)
- **Python**: [Python](https://marketplace.visualstudio.com/items?itemName=ms-python.python)

## Install a runtime

For code-based exercises, install the runtime that matches your chosen language. If you plan to try both language tracks, install both. Exercises that use only the portals and Azure CLI don't require a local .NET or Python installation.

| Runtime | Version |
| :--- | :--- |
| [.NET SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | 10.0 or later. Install the SDK, not the runtime. |
| [Python](https://www.python.org/downloads/) | 3.12 or 3.13. Select **Add python.exe to PATH** in the installer. |

## Install the per-exercise tools

Three exercises need extra software. Install these only when you reach the exercise that needs them.

| Exercise | Additional tools |
| :--- | :--- |
| Connect to Azure Cosmos DB with the SDK | [Azure Cosmos DB emulator](https://learn.microsoft.com/azure/cosmos-db/emulator) |
| Process the Azure Cosmos DB change feed | [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local) and [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) |
| Implement AI-assisted development tools | [Node.js 22](https://nodejs.org) or later, and the [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension for Visual Studio Code |

## Sign in to Azure

Open a terminal and sign in with the identity specified by your lab environment. The shared setup script uses that identity.

```azurecli
az login
```

If you have more than one subscription, set the one you want to use for this course:

```azurecli
az account set --subscription "<your-subscription-name>"
```

## Clone the lab repository

Several exercises reference files in this repository.

1. Start **Visual Studio Code**.
1. Open the command palette with **Ctrl+Shift+P** and run **Git: Clone**.
1. Enter `https://github.com/microsoftlearning/dp-420-cosmos-db-dev` and choose a local folder.
1. When cloning finishes, open the local folder in **Visual Studio Code**.

## Next step

Return to your exercise's setup steps. For help with the shared account setup, see [Create your Azure Cosmos DB account](00-create-cosmos-account.md).
