---
lab:
    title: 'Troubleshoot an application using the Azure Cosmos DB SQL API SDK'
    module: 'Module 11 - Monitor and troubleshoot an Azure Cosmos DB SQL API solution'
---

# Troubleshoot an application using the Azure Cosmos DB SQL API SDK

Azure Cosmos DB offers an extensive set of response codes, which help us easily troubleshoot issues that could arise with our different operation types. The catch is to make sure we program proper error handling when creating apps for Azure Cosmos DB.

In this lab, we'll create a menu driven program that will allow us to insert or delete one of two documents. The main purpose of this lab is to introduce us to how to use some of the most common response codes and how to use them in our app's error handling code.  While we'll code error handling for multiple response codes, we'll only trigger two different types of conditions.  Additionally the error handling won't do anything complex, depending on the response code, it will either display a message to the screen or wait 10 seconds and retry the operation one more time. 

## Prepare your development environment

If you haven't already cloned the lab code repository for **DP-420** to the environment where you're working on this lab, follow these steps to do so. Otherwise, open the previously cloned folder in **Visual Studio Code**.

1. Start **Visual Studio Code**.

    > &#128221; If you are not already familiar with the Visual Studio Code interface, review the [Get Started guide for Visual Studio Code][code.visualstudio.com/docs/getstarted]

1. Open the command palette and run **Git: Clone** to clone the ``https://github.com/microsoftlearning/dp-420-cosmos-db-dev`` GitHub repository in a local folder of your choice.

    > &#128161; You can use the **CTRL+SHIFT+P** keyboard shortcut to open the command palette.

1. Once the repository has been cloned, open the local folder you selected in **Visual Studio Code**.

## Create an Azure Cosmos DB SQL API account

Azure Cosmos DB is a cloud-based NoSQL database service that supports multiple APIs. When provisioning an Azure Cosmos DB account for the first time, you'll select which of the APIs you want the account to support (for example, **Mongo API** or **SQL API**). Once the Azure Cosmos DB SQL API account is done provisioning, you can retrieve the endpoint and key. Use the endpoint and key to connect to the Azure Cosmos DB SQL API account programatically. Use the endpoint and key on the connection strings of the Azure SDK for .NET or any other SDK.

1. In a new web browser window or tab, navigate to the Azure portal (``portal.azure.com``).

1. Sign into the portal using the Microsoft credentials associated with your subscription.

1. Select **+ Create a resource**, search for *Cosmos DB*, and then create a new **Azure Cosmos DB SQL API** account resource with the following settings, leaving all remaining settings to their default values:

    | **Setting** | **Value** |
    | ---: | :--- |
    | **Subscription** | *Your existing Azure subscription* |
    | **Resource group** | *Select an existing or create a new resource group* |
    | **Account Name** | *Enter a globally unique name* |
    | **Location** | *Choose any available region* |
    | **Capacity mode** | *Provisioned throughput* |
    | **Apply Free Tier Discount** | *`Do Not Apply`* |

    > &#128221; Your lab environments may have restrictions preventing you from creating a new resource group. If that is the case, use the existing pre-created resource group.

1. Wait for the deployment task to complete before continuing with this task.

1. Go to the newly created **Azure Cosmos DB** account resource and navigate to the **Keys** pane.

1. This pane contains the connection details and credentials necessary to connect to the account from the SDK. Specifically:

    1. Record the value of the **URI** field. You'll use this **endpoint** value later in this exercise.

    1. Record the value of the **PRIMARY KEY** field. You'll use this **key** value later in this exercise.

1. Minimize, but don't close your browser window. We'll come back to the Azure portal a few minutes after we start a background workload in the next steps.


## Import the Microsoft.Azure.Cosmos library into a .NET script

The .NET CLI includes an [add package][docs.microsoft.com/dotnet/core/tools/dotnet-add-package] command to import packages from a pre-configured package feed. A .NET installation uses NuGet as its default package feed.

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **26-sdk-troubleshoot** folder.

1. Open the context menu for the **26-sdk-troubleshoot** folder and then select **Open in Integrated Terminal** to open a new terminal instance.

    > &#128221; This command will open the terminal with the starting directory already set to the **26-sdk-troubleshoot** folder.

1. Add the [Microsoft.Azure.Cosmos][nuget.org/packages/microsoft.azure.cosmos/3.22.1] package from NuGet using the following command:

    ```
    dotnet add package Microsoft.Azure.Cosmos --version 3.22.1
    ```

## Run a script to create menu-driven options to insert and delete documents.

Before we can run our application, we need to connect it to our Azure Cosmos DB account. 

1. In **Visual Studio Code**, in the **Explorer** pane, browse to the **26-sdk-troubleshoot** folder.

1. Open the **Program.cs** code file.

1. Update the existing variable named **endpoint** with its value set to the **endpoint** of the Azure Cosmos DB account you created earlier.
  
    ```
    private static readonly string endpoint = "<cosmos-endpoint>";
    ```

    > &#128221; For example, if your endpoint is: **https&shy;://dp420.documents.azure.com:443/**, then the C# statement would be: **private static readonly string endpoint = "https&shy;://dp420.documents.azure.com:443/";**.

1. Update the existing variable named **key** with its value set to the **key** of the Azure Cosmos DB account you created earlier.

    ```
    private static readonly string key = "<cosmos-key>";
    ```

    > &#128221; For example, if your key is: **fDR2ci9QgkdkvERTQ==**, then the C# statement would be: **private static readonly string key = "fDR2ci9QgkdkvERTQ==";**.

1. Build and run the project using the [dotnet run][docs.microsoft.com/dotnet/core/tools/dotnet-run] command:

    ```
    dotnet run
    ```
    > &#128221; This is a very simple program.  It will display a menu with five options as show below. Two options to insert a predifined document, two to delete a predifined document, and an option to exit the program.

    >```
    >1) Add Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'
    >2) Add Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'
    >3) Delete Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'
    >4) Delete Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'
    >5) Exit
    >Select an option:
    >```

## Time to insert and delete documents.

1. Select **1** and **ENTER** to insert the first document. The program will insert the first document and return the following message.

    ```
    Insert Successful.
    Document for customer with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828' Inserted.
    Press [ENTER] to continue
    ```

1. Again, select **1** and **ENTER** to insert the first document. This time the program will crash with an exception. Looking through the error stack, we can find the reason for the program failure. As we can tell from the message extracted from the error stack, we come across an unhandle exception "Conflict (409)"

    ```
    Unhandled exception. Microsoft.Azure.Cosmos.CosmosException : Response status code does not indicate success: Conflict (409);
    ```

1. Since we're inserting a document, we'll need to review the list of common [create document status codes][/rest/api/cosmos-db/create-a-document#status-codes] returned when a document is created. The description of this code is, *the ID provided for the new document has been taken by an existing document*. This is obvious, since we just ran the menu option to create the same document a few moments ago.

1. Digging further into the stack, we can see that this exception was called from line 99, and that in turn was called from line 52.

    ```
    at Program.CreateDocument1(Container Customer) in C:\WWL\Git\DP-420\Git\dp-420-cosmos-db-dev\26-sdk-troubleshoot\Program.cs:line 97   at Program.Main(String[] args) in C:\WWL\Git\DP-420\Git\dp-420-cosmos-db-dev\26-sdk-troubleshoot\Program.cs:line 50
    ```

1. Reviewing line 97, as expected, the error was caused by the CreateItemAsync operation. 

```C#
            ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
```

1. Furthermore, by reviewing lines 97 to 99, it's obvious that this code has no error handling. We'll need to fix that.

```C#
            ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
            Console.WriteLine("Insert Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");
```

1. We'll need to decide what our error-handling code should do. Reviewing the [create document status codes][/rest/api/cosmos-db/create-a-document#status-codes], we could choose to create error-handling code for every possible status code for this operation.  In this lab, we will only consider from this list, status Code 403 a 409.  All other status codes retuned will just display the system error message.

    > &#128221; Note that while we will code a task to do if we encounter a 403 exception, in this lab we will not generate that type of an error with exception.

1. Let's replace the code from lines 96-100 with the following code. The first thing to notice in this new code, is that on the **catch** we're capturing an exception of type `CosmosException` class.  This class included the property `StatusCode`, which gets the request completion status code from the Azure Cosmos DB service. The `StatusCode` property is of type `System.Net.HttpStatusCode`, so if you notice we actually compare its value against the field names from the .NET [HTTP Status Code][dotnet/api/system.net.httpstatuscode].  

```C#
            try
            {
               ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
               Console.WriteLine("Insert Successful.");
               Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");

            }
            catch (CosmosException e)
            {
                switch (e.StatusCode.ToString())
                {
                    case ("Conflict"):
                        Console.WriteLine("Insert Failed. Response Code (409).");
                        Console.WriteLine("Can not insert a duplicate partition key, customer with id = '" + customerID + "' already exists.");
                        break;
                    case ("Forbidden"):
                        Console.WriteLine("Response Code (403).");
                        Console.WriteLine("The request was forbidden to complete. Some possible reasons for this exception are:");
                        Console.WriteLine("Firewall blocking requests.");
                        Console.WriteLine("Partition key exceeding storage.");
                        Console.WriteLine("Non-data operations are not allowed.");
                        break;
                    default:
                        Console.WriteLine(e.Message);
                        break;
                }

            }

```

1. Save the file and since we crashed, we need to run our Menu program again, so run the command:

    ```
    dotnet run
    ```
 
1. Again, select **1** and **ENTER** to insert the first document. This time we don't crash but get a more user-friendly message of what happened.

    ```
    Insert Failed. 
    Response Code (409).
    Can not insert a duplicate partition key, customer with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828' already exists.
    Press [ENTER] to continue
    ```

1. While it's good that we're taking care of two specific exceptions for our document creation, 403 and 409, there are three other communication type of exceptions that any type of operation could experience.  These exceptions are 429, 503, and 408 or too many request, service unavailable, and request time out respectively. We'll add some code that will do the following, if we find any of these exceptions, wait 10 minutes, and then try to insert the document one more time.  Lets' replace the code:

```C#
                    default:
                        Console.WriteLine(e.Message);
                        break;
```

For:

```C#
                    default:
                        // Check if the issues are related to connectivity and if so, wait 10 seconds to retry.
                        if (e.StatusCode.ToString() == "TooManyRequests" // 429
                                || e.StatusCode.ToString() == "ServiceUnavailable" // 503
                                || e.StatusCode.ToString() == "RequestTimeout") // 408
                        {
                            Thread.Sleep(10000); // Wait 10 seconds
                            try
                            {
                                ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
                                Console.WriteLine("Insert Successful.");
                                Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");

                            }
                            catch (CosmosException e2)
                            {
                                Console.WriteLine("Insert Failed. " + e2.Message);
                                Console.WriteLine("Can not insert a duplicate partition key, customer with id = '" + customerID + "', Connectivity issues encountered.");
                                break;
                            }

                        }
                        else
                            Console.WriteLine(e.Message);
                        break;
```

> &#128221; Note that while we will code a task of what to do if we encounter a 429, 503 or 408 exception, in this lab we will not generate an error with that type of exception.

1. Our `CreateDocument1` function should now look something like this:

```C#
    static async Task CreateDocument1(Container Customer)
    {
            string customerID = "0C297972-BE1B-4A34-8AE1-F39E6AA3D828";
            PartitionKey pKey = new PartitionKey(customerID);
            
            customerInfo customer = new customerInfo();

            customer.id = customerID;
            customer.title = "";
            customer.firstName="Franklin";
            customer.lastName="Ye";
            customer.emailAddress="franklin9@adventure-works.com";
            customer.phoneNumber= "1 (11) 500 555-0139";
            customer.creationDate = "2014-02-05T00:00:00";

            Console.Clear();

            try
            {
               ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
               Console.WriteLine("Insert Successful.");
               Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");

            }
            catch (CosmosException e)
            {
                switch (e.StatusCode.ToString())
                {
                    case ("Conflict"):
                        Console.WriteLine("Insert Failed. Response Code (409).");
                        Console.WriteLine("Can not insert a duplicate partition key, customer with id = '" + customerID + "' already exists.");
                        break;
                    case ("Forbidden"):
                        Console.WriteLine("Response Code (403).");
                        Console.WriteLine("The request was forbidden to complete. Some possible reasons for this exception are:");
                        Console.WriteLine("Firewall blocking requests.");
                        Console.WriteLine("Partition key exceeding storage.");
                        Console.WriteLine("Non-data operations are not allowed.");
                        break;
                    default:
                        // Check if the issues are related to connectivity and if so, wait 10 seconds to retry.
                        if (e.StatusCode.ToString() == "TooManyRequests" // 429
                                || e.StatusCode.ToString() == "ServiceUnavailable" // 503
                                || e.StatusCode.ToString() == "RequestTimeout") // 408
                        {
                            Thread.Sleep(10000); // Wait 10 seconds
                            try
                            {
                                ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
                                Console.WriteLine("Insert Successful.");
                                Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");

                            }
                            catch (CosmosException e2)
                            {
                                Console.WriteLine("Insert Failed. " + e2.Message);
                                Console.WriteLine("Can not insert a duplicate partition key, customer with id = '" + customerID + "', Connectivity issues encountered.");
                                break;
                            }

                        }
                        else
                            Console.WriteLine(e.Message);
                        break;
                }

            }

            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();

        
    }
```

1. The `CreateDocument2` function will also need to be fixed. Replace the following code for the proper error-handling code we included in the `CreateDocument1` function.

```C#
               ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
               Console.WriteLine("Insert Successful.");
               Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");
```

1. Finally the functions DeleteDocument1 and DeleteDocument2 also need the following code to be replaced for the proper error-handling code similar to the `CreateDocument1` function. The only difference with these functions besides using **DeleteItemAsync** instead of **CreateItemAsync** is that [deletes status codes][/rest/api/cosmos-db/delete-a-document] are different than the insert status codes. For the deletes, we only care about a **404** status code. Go ahead and replace this code on both delete functions with code that does some error handling. Also include the retry logic for status code **429**, **503** and **508**.

```C#
            ItemResponse<customerInfo> response = await Customer.DeleteItemAsync<customerInfo>(partitionKey: new PartitionKey(customerID), id: customerID);
            Console.WriteLine("Delete Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Deleted.");
```

1. Once you're done fixing all functions, test all the menu options several times to make sure you that your app is returning a message when encountering an exception and not crashing.  If your app crashes, fix the errors and just rerun the command:

    ```
    dotnet run
    ```


1. Don't peek, but once you're done, your delete codes should look something like this.

```C#
    static async Task DeleteDocument1(Container Customer)
    {
            string customerID = "0C297972-BE1B-4A34-8AE1-F39E6AA3D828";
            
            Console.Clear();

            try
            {
               ItemResponse<customerInfo> response = await Customer.DeleteItemAsync<customerInfo>(partitionKey: new PartitionKey(customerID), id: customerID);
               Console.WriteLine("Delete Successful.");
               Console.WriteLine("Document for customer with id = '" + customerID + "' Deleted.");

            }
            catch (CosmosException e)
            {
                switch (e.StatusCode.ToString())
                {
                    case ("NotFound"):
                        Console.WriteLine("Delete Failed. Response Code (404).");
                        Console.WriteLine("Can not delete customer with id = '" + customerID + "', customer not found.");
                        break;
                    default:
                        // Check if the issues are related to connectivity and if so, wait 10 seconds to retry.
                        if (e.StatusCode.ToString() == "TooManyRequests" // 429
                                || e.StatusCode.ToString() == "ServiceUnavailable" // 503
                                || e.StatusCode.ToString() == "RequestTimeout") // 408
                        {
                            Thread.Sleep(10000); // Wait 10 seconds
                            try
                            {
                                ItemResponse<customerInfo> response = await Customer.DeleteItemAsync<customerInfo>(partitionKey: new PartitionKey(customerID), id: customerID);
                                Console.WriteLine("Delete Successful.");
                                Console.WriteLine("Document for customer with id = '" + customerID + "' Deleted.");
                            }
                            catch (CosmosException e2)
                            {
                                Console.WriteLine("Delete Failed. " + e2.Message);
                                Console.WriteLine("Can not delete customer with id = '" + customerID + "', customer not found.");
                                break;
                            }

                        }
                        else
                            Console.WriteLine(e.Message);
                        break;
                }

            }

            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();
    }
```

## Conclusion

Even the most junior developers knows that proper error handling must be added to all code. While the error handling in this code is simple, it should have given you the basics about the Azure Cosmos DB exception components that will let you create robust error-handling solutions in your code.


[code.visualstudio.com/docs/getstarted]: https://code.visualstudio.com/docs/getstarted/tips-and-tricks
[docs.microsoft.com/dotnet/core/tools/dotnet-add-package]: https://docs.microsoft.com/dotnet/core/tools/dotnet-add-package
[docs.microsoft.com/dotnet/core/tools/dotnet-run]: https://docs.microsoft.com/dotnet/core/tools/dotnet-run
[nuget.org/packages/microsoft.azure.cosmos/3.22.1]: https://www.nuget.org/packages/Microsoft.Azure.Cosmos/3.22.1
[/rest/api/cosmos-db/create-a-document#status-codes]:https://docs.microsoft.com/rest/api/cosmos-db/create-a-document#status-codes
[dotnet/api/system.net.httpstatuscode]:https://docs.microsoft.com/dotnet/api/system.net.httpstatuscode?view=net-6.0
[/rest/api/cosmos-db/delete-a-document]:https://docs.microsoft.com/rest/api/cosmos-db/delete-a-document#status-codes

