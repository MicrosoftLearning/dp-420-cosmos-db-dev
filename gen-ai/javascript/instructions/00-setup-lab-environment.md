---
title: 'Setup lab environment'
lab:
    title: 'Setup lab environment'
    module: 'Setup'
layout: default
nav_order: 2
parent: 'JavaScript SDK labs'
---

# Setup local lab environment

Ideally, you should complete these labs in a hosted lab environment. If you want to complete them on your own computer, you can do so by installing the following software. You may experience unexpected dialogs and behavior when using your own environment. Due to the wide range of possible local configurations, the course team cannot support issues you may encounter in your own environment.

## Azure command-line tools

1. [Azure CLI](https://docs.microsoft.com/cli/azure/?view=azure-cli-latest) or [Azure Cloud Shell](https://shell.azure.com) - Install if you want to execute commands via the CLI instead of the Azure portal.

## Node.js

1. Download and install Node.js v18.0.0 or newer from [nodejs.org/en/download].

1. Download and install NPM v10.2.3 or newer from [npmjs.com/get-npm].

Recommended way to install the latest version of NPM and node.js on Windows:

- Install NVM from [github.com/coreybutler/nvm-windows]
- Run nvm install latest
- Run nvm list (to see the versions of NPM/node.js available)
- Run nvm use latest (to use the latest available version)

### Git

1. Download and install from [git-scm.com/downloads].

    - Use the default options in the installer.

### Visual Studio Code (and extensions)

1. Download and install from [code.visualstudio.com/download].

    - Use the default options in the installer.

1. After installation, start Visual Studio Code.

### Azure Cosmos DB Emulator

1. Download and install from [docs.microsoft.com/azure/cosmos-db/local-emulator].
    - Use the default options in the installer.

### Clone the lab repository

If you have not already cloned the lab code repository for **Build copilots with Azure Cosmos DB** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/solliancenet/microsoft-learning-path-build-copilots-with-cosmos-db-labs`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, open the local folder you selected in **Visual Studio Code**.

[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks

[docs.microsoft.com/azure/cosmos-db/local-emulator]: https://docs.microsoft.com/azure/cosmos-db/local-emulator#download-the-emulator
[code.visualstudio.com/download]: https://code.visualstudio.com/download
[git-scm.com/downloads]: https://git-scm.com/downloads
[nodejs.org/en/download]: https://nodejs.org/en/download
[npmjs.com/get-npm]: https://npmjs.com/get-npm
[github.com/coreybutler/nvm-windows]: https://github.com/coreybutler/nvm-windows
