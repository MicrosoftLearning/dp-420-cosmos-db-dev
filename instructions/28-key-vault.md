---
lab:
    title: 'Store Azure Cosmos DB for NoSQL account keys in Azure Key Vault'
    module: 'Module 11 - Monitor and troubleshoot an Azure Cosmos DB for NoSQL solution'
---

# Store Azure Cosmos DB for NoSQL account keys in Azure Key Vault

Adding an Azure Cosmos DB account connection code to your application is as simple as providing the account's URI and keys. This security information might sometimes be hard-coded into the application code. However, if your application is being deployed to the Azure App Service, you can save the encrypt connection information into Azure Key Vault.

In this lab, we'll encrypt and store the Azure Cosmos DB account connection string into the Azure Key Vault. We will then create an Azure App Service webapp that will retrieve those credentials from the Azure Key Vault. The application will use these credentials and connect to the Azure Cosmos DB account. The application will then create some documents in the Azure Cosmos DB account containers and return its status back to a web page.

## Prepare your development environment

If you haven't already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/microsoftlearning/dp-420-cosmos-db-dev`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, ***CLOSE*** *Visual Studio Code*. We will later open it pointing directly to the **28-key-vault** folder.

## Create an Azure Cosmos DB for NoSQL account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you'll select which of the APIs you want the account to support (for example, **Mongo API** or **NoSQL API**). Once the Azure Cosmos DB for NoSQL account is done provisioning, you can retrieve the endpoint and key. Use the endpoint and key to connect to the Azure Cosmos DB for NoSQL account programatically. Use the endpoint and key on the connection strings of the Azure SDK for .NET or any other SDK.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB for NoSQL** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |
    | **Apply Free Tier Discount** | *Do Not Apply* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically the **PRIMARY CONNECTION STRING** field. You'll use this **connection string** value later in this exercise.

## Create an Azure Key Vault and store the Azure Cosmos DB account credentials as a secret

Before we create our web app, we will secure the Azure Cosmos DB account connection string by copying them to an *Azure Key Vault* encrypted *secret*. Let's do that now.

1. In a new browser tab, navigate to the Azure portal, opening the **Key vaults** page.

1. Add a vault by selecting the ***+ Create*** button, and fill out the vault with the following settings, *leaving all remaining settings to their default values*, then select to create the vault:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Key vault name** | *Enter a globally unique name* |
    | **Region** | *Choose any available region* |
    | **Access Configuration/Permission model** | *Vault Access Policy* |
    | **Access Configuration/Access policies** | *select the current username checkbox* |

    > &#128221; Note, in a production environment you would most likely select RBAC control instead of Vault Access policy, and your administrator will most likely assign you the proper RBAC role to limit your Key Vault access .

1. Once the vault is created, navigate to the vault.

1. Under the *Objects* section, select **Secrets**.

1. Select the **+ Generate/Import** to encrypt our credential connection string and fill in the *secret* values with the following settings, *leaving all remaining settings to their default values*, then select to create the secret:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Upload options** | *Manual* |
    | **Name** | *The name you will label your secret with* |
    | **Value** | *This field is the most important field to fill out. Copy here value of the PRIMARY CONNECTION STRING from the key section of your Azure Cosmos DB account. This value will be convert into a secret.* |
    | **Enabled** | *Yes* |
 
1. Under the Secrets, you should now see your new secret listed. We need to get the *secret identifier* that we will add to the code of our webapp. Select the **secret** you created.

1. Azure Key Vault allows you to create multiple versions of your secret, but for this lab, we only need one version. Select the **Current version**.

1. Record the value of the **Secret Identifier** field. This value is what we will use in our application's code to get the secret from the Key Vault.  Notice that this value is a URL. There is one more step we need to get this secret working properly, but we will do that step a little later.

## Create an Azure App Service webapp

We'll create a webapp that will connect to the Azure Cosmos DB account and create some containers and documents. We won't hard code the Azure Cosmos DB *credentials* in this app, but instead, hard code the **Secret Identifier** from the key vault. We'll see how this identifier is useless without the proper rights assigned to the webapp on the Azure layer. Let's start coding.



1. Open **Visual Studio Code**.  Open the **28-key-vault** folder, by selecting File->Open folder, and browsing all the way into the **28-key-vault** folder.

    > &#128221; Note, you should only see the **28-key-vault** folder and its files and subfolders in the **Explorer** tree. If you can see the whole GitHub repository we cloned earlier, ***Close Visual Studio Code*** and reopen it directly to the **28-key-vault** folder.  The web app will not work correctly if that directory is not your projects root directory, so make sure you can only see the **28-key-vault** folder and its files and subfolder in the **Explorer** tree.

1. Open the context menu for the **28-key-vault** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **28-key-vault** folder.

1. Let's create an MVC webapp shell. We will replace a couple of the generated files in a moment. Run the following command to create the webapp:

    ```
    dotnet new mvc
    ```


    > &#128221;This command created the shell of a web app, so it added several files and directories. We already have a couple of files with all the code we need. 

1. Replace the files **.\Controllers\HomeController.cs** and **.\Views\Home\Index.cshtml** for their respective files from the **.\KeyvaultFiles** directory.

1. Once you replace the files ***DELETE*** the **.\KeyvaultFiles** directory.

## Import the multiple missing libraries into the .NET script

The .NET CLI includes an [add package][docs.microsoft.com/dotnet/core/tools/dotnet-add-package] command to import packages from a pre-configured package feed. A .NET installation uses NuGet as its default package feed.

1. Add the [Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Cosmos --version 3.22.1
    ```

1. Add the [Newtonsoft.Json][nuget.org/packages/Newtonsoft.Json/13.0.1] package from NuGet using the following command:

    ```
    dotnet add package Newtonsoft.Json --version 13.0.1
    ```

1. Add the [Microsoft.Azure.KeyVault][nuget.org/packages/Microsoft.Azure.KeyVault] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.KeyVault
    ```

1. Add the [Microsoft.Azure.Services.AppAuthentication][nuget.org/packages/Microsoft.Azure.Services.AppAuthentication] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Services.AppAuthentication --version 1.6.2
    ```

## Adding the Secret Identifier to your webapp

1. In visual studio, open the `.\Controllers\HomeControler.cs` file

1. The **GetKeyVaultSecret** user-defined function will get the Azure Cosmos DB account secret. The function start in *line 98*, should look like the script below.

```
        private static async Task<Tuple<bool,string>>  GetKeyVaultSecret()
        {
            AzureServiceTokenProvider azureServiceTokenProvider = new AzureServiceTokenProvider("RunAs=App;");

            try
            {
                var KVClient = new KeyVaultClient(
                    new KeyVaultClient.AuthenticationCallback(azureServiceTokenProvider.KeyVaultTokenCallback));

                var KeyVaultSecret = await KVClient.GetSecretAsync("<Key Vault Secret Identifier>")
                    .ConfigureAwait(false);

                return new Tuple<bool,string>(true, KeyVaultSecret.Value.ToString());

            }
            catch (Exception exp)
            {
                return new Tuple<bool,string>(false, exp.Message);
            }

        }
```

3. Let's review the important calls this function makes.

    - In *line 100*, we define the token of the current web app. This token will be provided to the Azure Key Vault to identify what app is trying to access the vault. 
    - In *line 104-105*, we prepare the *Key Vault Client* that will connect to the Azure Key Vault. Notice we send the webapp token as a parameter. 
    - In *lines 107-108*, we provide the Key Vault Client with the URL address of our **Secret Identifier** which would return the secret stored in that key vault. 

1.  Before we can deploy our webapp, we still need to send the **Secret Identifier** URL.  On *line 107*, replace the string ***<Key Vault Secret Identifier>*** with the **Secret Identifier** URL we recorded in the *secret* section and save the file.

```
        var KeyVaultSecret = await KVClient.GetSecretAsync("<Key Vault Secret Identifier>")
```

## (Optional) Install the Azure App Services Extension

In Visual studio, if you bring up the command pallet (**CTRL+SHIFT+P**), and it does not return anything when searching for Azure App Resource commands, we need to install the extension.

1. In Visual Studio Code left-hand menu, select the **Extensions** option.

1. In the search bar, search for Azure App Service and select it.

1. Select the Install button to install it.

1. Close the **Extensions** Tab and go back to your code.

## Deploy your application to Azure App Services

The rest of the code is straight forward, get the connection string, connect to Azure Cosmos DB, and add some documents. The application should also provide us with some feedback on any issues. We should not need to do any more changes after we deploy the application. Let's get started. 

> &#128221; Most of the steps below will be run in the command pallet (**CTRL+SHIFT+P**) in the upper middle of your Visual Studio screen. 

1. In Visual Studio Code, open the command pallet, search for ***Azure App Service: Create New Web App ... (Advanced)***

1. Select ***Sign-in to Azure...***. This option will open a web browser window, follow the sign-in process, and close the browser when done and return to Visual Studio Code.

1. (Optional) If it asks for your subscription select your subscription.

1. Enter a globally unique name for your web app.

1. Select an existing Resource Group or create a new one if needed.

1. Select **.NET 6 (LTS)**.

1. Select **Windows**.

1. Select an available Location.

1. Select  **+ Create a new App Service Plan**.

1. Accept the default name for the App Service Plan (it should be the same as your web app name), or pick a new name.

1. Select **Free (F1) Try out Azure at no cost**.

1. Select **Skip for now** for the Application Insights.

1. The deployment should now be running with a status bar in the lower right-hand corner. 

1. Select **Deploy** when prompted.

1. Select **Browse** and you should be inside the **28-key-vault** folder, Select that folder.

1. A popup with the message **Required configuration to deploy is missing from "28-key-vault"** should appear, select the Add Config button.  This option will create the missing `.vscode` folder.

    > &#128221; Very important, if this pop-up does not appear on your first deployment of the app, the upload to the Azure App Services will be missing files. The deployment will succeed, but the website will always return the message *You do not have permission to view this directory or page.*. The most likely culprit is that Visual Studio Code was opened on the GitHub Cloned repository instead of only the  **28-key-vault** folder.

1. Select **Yes** when prompted to always deploy to that workspace.

1. Select **Browse Website** when prompted.  Alternatively, open a browser and go to **`https://<yourwebappname>.azurewebsites.net`**. In either case, we have a problem. You will see a user-defined message on our web page. The message should be, **Key Vault was not accessible** with an extended error message. Let's fix that.

## Allow our app to use a managed identity

The first problem we need to fix is to allow our app use a managed identity. Using a managed identity will allow our app to use Azure Services like Azure Key Vault.

1. Open up your browser and login to the Azure portal.

1. Open up the **App Services** page. Your webapp name should be listed, select it.

1. Under the *Settings* section, select **Identity**.

1. Under Status, select **On** and **Save**.  Select **Yes** if prompted to enable the *Assigned Managed Identity*.

1. Let's try our web app again.  On your browser, go to  **`https://<yourwebappname>.azurewebsites.net`**.

1. There is still one problem. While the first message is a user-defined message our program is sending, the second one is a System generated one. What the second message means is that we have been granted access to the connect to the Key vault, but we have not been granted access to view the secret inside the vault.  Let's set one final setting to fix this issue.

## Granting our web application an access policy to the Key Vault secrets

The original goal of this lab was to prevent our Azure Cosmos DB Accounts from being hard-coded in our applications. But, we did hard coded our **Secret Identifier** URL which anybody can see. So how can we secure our credentials? The good news is that the Secret Identifier by itself is useless. The **Secret Identifier** only gets you to the Azure Key vault door, but the vault will decide who comes in and who stays at the door. What this means is that we'll need to create a Key Vault access policy for our application so it can see the secrets in that vault. Let's take a look at that solution.

1. (Optional) Before we create the policy let's review the current content of our Azure Cosmos DB database.  In the Azure portal go to your Azure Cosmos DB account, is there a **GlobalCustomers** Database? If it isn't there, it will be created by the successful run of the web app. If it is there, review the number of items in the database, and the successful run of the web app will add more items.

1. In the Azure portal, go to the Key vault we created earlier.

1. Under the *Settings* section, select **Access configuration**.

1. Ensure **Vault access policy** is selected, and then select **Go to access policies**.

1. Select **+ Create**.

1. On the **Permissions** tab, select the **Get** checkbox for **Key permissions** and **Secret permissions**, and then select **Next**.

1. On the **Principal** tab, in the search box, enter the name you gave your App Service, select it from the list, and then select **Next**.

1. On the **Application (optional)** tab, select **Next**.
    
1. On the **Review + create** tab, select **Create**.

1. Let's try our web app again.  On your browser, go to  **`https://<yourwebappname>.azurewebsites.net`**.

1. Success! Our web page should indicate that we inserted new items into the customer container. We can also see the actual Secret being displayed.

    > &#128221; In a production environment **never** display the secret, this was just done for illustration purposes.


1. Go to your Azure Cosmos DB account and verify that you either have a new **GlobalCustomers** database with data in it, or if the database already existed, if there are now more items in the database.

We have now successfully used Azure Key Vault to protect the keys of your Azure Cosmos DB account.
