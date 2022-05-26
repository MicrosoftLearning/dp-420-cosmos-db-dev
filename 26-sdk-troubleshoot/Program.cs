using System;
using System.Threading.Tasks;
using Microsoft.Azure.Cosmos;
using System.Threading;

public class Program
{    

    private static readonly string endpoint = "<cosmos-endpoint>";
    private static readonly string key = "<cosmos-key>";

    private static readonly string connectionString = "AccountEndpoint=" + endpoint + ";AccountKey=" + key;

    public class customerInfo
    { 
        public string id {get;set;} = "";
        public string title {get;set;} = "";
        public string firstName {get;set;} = "";
        public string lastName {get;set;} = "";
        public string emailAddress {get;set;} = "";
        public string phoneNumber {get;set;} = "";
        public string creationDate {get;set;} = "";
    }

    public static async Task Main(string[] args)
    {

        CosmosClient client = new CosmosClient(connectionString,new CosmosClientOptions() { AllowBulkExecution = true, MaxRetryAttemptsOnRateLimitedRequests = 50, MaxRetryWaitTimeOnRateLimitedRequests = new TimeSpan(0,1,30)});

        Console.WriteLine("Creating Azure Cosmos DB Databases and containers");

        Database CustomersDB = await client.CreateDatabaseIfNotExistsAsync("CustomersDB");
        Container CustomersDB_Customer_container = await CustomersDB.CreateContainerIfNotExistsAsync(id: "Customer", partitionKeyPath: "/id", throughput: 400);

        Console.Clear();
        Console.WriteLine("1) Add Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'");
        Console.WriteLine("2) Add Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'");
        Console.WriteLine("3) Delete Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'");
        Console.WriteLine("4) Delete Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'");
        Console.WriteLine("5) Exit");
        Console.Write("\r\nSelect an option: ");
 
        string consoleinputcharacter;
    
        while((consoleinputcharacter = Console.ReadLine()) != "5") 
        {
            await CompleteTaskOnCosmosDB(consoleinputcharacter, CustomersDB_Customer_container);

            Console.WriteLine("Choose an action:");
            Console.WriteLine("1) Add Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'");
            Console.WriteLine("2) Add Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'");
            Console.WriteLine("3) Delete Document 1 with id = '0C297972-BE1B-4A34-8AE1-F39E6AA3D828'");
            Console.WriteLine("4) Delete Document 2 with id = 'AAFF2225-A5DD-4318-A6EC-B056F96B94B7'");
            Console.WriteLine("5) Exit");
            Console.Write("\r\nSelect an option: ");
        }
    }

    public static async Task CompleteTaskOnCosmosDB(string consoleinputcharacter, Container container)
    {
        switch (consoleinputcharacter)
        {
            case "1":
                await CreateDocument1(container);
                break;
            case "2":
                await CreateDocument2(container);
                break;
            case "3":
                await DeleteDocument1(container);
                break;
            case "4":
                await DeleteDocument2(container);
                break;
            case "5":
                break;
            default:
                Console.WriteLine("Default");
                break;
        }
        Console.Clear();
    }
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

            ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
            Console.WriteLine("Insert Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");

            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();
        
    }
    static async Task CreateDocument2(Container Customer)
    {
            string customerID = "AAFF2225-A5DD-4318-A6EC-B056F96B94B7";
            
            customerInfo customer = new customerInfo();

            customer.id = customerID;
            customer.title = "";
            customer.firstName="Michael";
            customer.lastName="Gonzalez";
            customer.emailAddress="mgonz01@adventure-works.com";
            customer.phoneNumber= "1 (44) 500 555-6612";
            customer.creationDate = "2016-08-27T00:00:00";

            Console.Clear();

            ItemResponse<customerInfo> response = await Customer.CreateItemAsync<customerInfo>(customer, new PartitionKey(customerID));
            Console.WriteLine("Insert Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Inserted.");
        
            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();
    }

    static async Task DeleteDocument1(Container Customer)
    {
            string customerID = "0C297972-BE1B-4A34-8AE1-F39E6AA3D828";
            
            Console.Clear();

            ItemResponse<customerInfo> response = await Customer.DeleteItemAsync<customerInfo>(partitionKey: new PartitionKey(customerID), id: customerID);
            Console.WriteLine("Delete Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Deleted.");

        
            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();
    }
    static async Task DeleteDocument2(Container Customer)
    {
            string customerID = "AAFF2225-A5DD-4318-A6EC-B056F96B94B7";
            
            Console.Clear();

            ItemResponse<customerInfo> response = await Customer.DeleteItemAsync<customerInfo>(partitionKey: new PartitionKey(customerID), id: customerID);
            Console.WriteLine("Delete Successful.");
            Console.WriteLine("Document for customer with id = '" + customerID + "' Deleted.");
        
            Console.WriteLine("Press [ENTER] to continue");
            Console.ReadLine();
    }

}
