using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Azure.Cosmos;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.IO;

public class Program
{

    private static readonly string endpoint = "<cosmos-endpoint>";
    private static readonly string key = "<cosmos-key>";

    private static readonly string connectionString = "AccountEndpoint=" + endpoint + ";AccountKey=" + key;


    public static async Task Main(string[] args)
    {

        CosmosClient client = new CosmosClient(connectionString,new CosmosClientOptions() { AllowBulkExecution = true, MaxRetryAttemptsOnRateLimitedRequests = 50, MaxRetryWaitTimeOnRateLimitedRequests = new TimeSpan(0,1,30)});

        Console.WriteLine("Creating Azure Cosmos DB Databases and containters");

        //Database database1 = await client.CreateDatabaseIfNotExistsAsync("database-v1");
        //Container database1_salesOrderDetail_container = await database1.CreateContainerIfNotExistsAsync(id: "salesOrderDetail", partitionKeyPath: "/id", throughput: 400);

        Database database2 = await client.CreateDatabaseIfNotExistsAsync("database-v2");
        Container database2_salesOrder_container;
        database2_salesOrder_container = database2.GetContainer("salesOrder");
        try
        {
            ContainerResponse response_database2_salesOrder_container = await database2_salesOrder_container.DeleteContainerAsync();
        }
        catch {}
        database2_salesOrder_container = await database2.CreateContainerIfNotExistsAsync(id: "salesOrder", partitionKeyPath: "/id", throughput: 10000);

        Database database3 = await client.CreateDatabaseIfNotExistsAsync("database-v3");
        Container database3_customer_container;
        Container database3_salesOrder_container;
        database3_customer_container = database3.GetContainer("customer");
        try
        {
            ContainerResponse response_database3_customer_container = await database3_customer_container.DeleteContainerAsync();
        }
        catch {}
        database3_salesOrder_container = database3.GetContainer("salesOrder");
        try
        {
            ContainerResponse response_database3_salesOrder_container = await database3_salesOrder_container.DeleteContainerAsync();
        }
        catch {}
        database3_customer_container =await database3.CreateContainerIfNotExistsAsync(id: "customer", partitionKeyPath: "/id", throughput: 10000);
        database3_salesOrder_container =await database3.CreateContainerIfNotExistsAsync(id: "salesOrder", partitionKeyPath: "/id", throughput: 10000);

        //Database database4 = await client.CreateDatabaseIfNotExistsAsync("database-v4");
        //Container database4_customer_container =await database4.CreateContainerIfNotExistsAsync(id: "customer", partitionKeyPath: "/id", throughput: 400);


        //JArray database1_salesOrderDetail = (JArray) JArray.Parse(File.ReadAllText(@"..\data\fullset\database-v1\salesOrderDetail"));
        JArray database2_salesOrder = (JArray) JArray.Parse(File.ReadAllText(@"..\data\fullset\database-v2\salesOrder"));
        JArray database3_customer = (JArray) JArray.Parse(File.ReadAllText(@"..\data\fullset\database-v3\customer"));
        JArray database3_salesOrder = (JArray) JArray.Parse(File.ReadAllText(@"..\data\fullset\database-v2\salesOrder"));
        //JArray database4_customer = (JArray) JArray.Parse(File.ReadAllText(@"..\data\fullset\database-v4\customer"));

        Console.WriteLine("");
        DateTime CurrentTime = DateTime.Now;
        Console.WriteLine(CurrentTime.ToString(@"MM\/dd\/yyyy hh:mm:ss tt"));
        Console.WriteLine("Inserting data into database-v2");

        List <Task> AddDocumentTask = new List<Task>();

        for (int recordcounter = 0; recordcounter < database2_salesOrder.Count; recordcounter++)
        {
            AddDocumentTask.Add(database2_salesOrder_container.CreateItemAsync(database2_salesOrder[recordcounter]));
            
                
        }
        await Task.WhenAll(AddDocumentTask);
        await database2_salesOrder_container.ReplaceThroughputAsync(400);

        TimeSpan LoadTime = DateTime.Now.Subtract(CurrentTime);

        Console.WriteLine("Loaded " + database2_salesOrder.Count.ToString() + " items into the database-v2 salesOrder container in " + LoadTime.ToString(@"mm\:ss"));

        Console.WriteLine("");
        CurrentTime = DateTime.Now;
        Console.WriteLine(CurrentTime.ToString(@"MM\/dd\/yyyy hh:mm:ss tt"));
        Console.WriteLine("Inserting data into database-v3");

        AddDocumentTask = new List<Task>();

        for (int recordcounter = 0; recordcounter < database3_salesOrder.Count; recordcounter++)
        {
            AddDocumentTask.Add(database3_salesOrder_container.CreateItemAsync(database3_salesOrder[recordcounter]));
            
                
        }
        await Task.WhenAll(AddDocumentTask);
        await database3_salesOrder_container.ReplaceThroughputAsync(400);

        LoadTime = DateTime.Now.Subtract(CurrentTime);
        CurrentTime = DateTime.Now;

        Console.WriteLine("Loaded " + database3_salesOrder.Count.ToString() + " items into the database-v3 salesOrder container in " + LoadTime.ToString(@"mm\:ss"));
        Console.WriteLine(DateTime.Now.ToString(@"MM\/dd\/yyyy hh:mm:ss tt"));

        AddDocumentTask = new List<Task>();

        for (int recordcounter = 0; recordcounter < database3_customer.Count; recordcounter++)
        {
            AddDocumentTask.Add(database3_customer_container.CreateItemAsync(database3_customer[recordcounter]));
            
                
        }
        await Task.WhenAll(AddDocumentTask);
        await database3_customer_container.ReplaceThroughputAsync(400);

        LoadTime = DateTime.Now.Subtract(CurrentTime);
        CurrentTime = DateTime.Now;

        Console.WriteLine("Loaded " + database3_customer.Count.ToString() + " items into database-v3 customer container in " + LoadTime.ToString(@"mm\:ss"));
        Console.WriteLine(DateTime.Now.ToString(@"MM\/dd\/yyyy hh:mm:ss tt"));

        Console.WriteLine("");
        Console.WriteLine("Creating simulated background workload, wait 5-10 minutes and go to the next step of the exercise.");
        Console.WriteLine(DateTime.Now.ToString(@"MM\/dd\/yyyy hh:mm:ss tt"));

       await CreateSimulatedLoad(client);
    }

    static async Task CreateSimulatedLoad(CosmosClient client)
    {
        string [] SQLScript = new string[7];
        SQLScript[0] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[1] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE NOT EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[2] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE NOT EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[3] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE NOT EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[4] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[5] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details WHERE EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12) AND EXISTS (SELECT VALUE n FROM n IN sO.details WHERE n.price > 12)";
        SQLScript[6] = "SELECT sO.customerId FROM salesOrder sO JOIN d in sO.details";

        string DatabaseName = "";
        string ContainerName = "";
        string SQLScriptToRun = "";

        int RandomDelayInSeconds;
        int RandomDatabaseNumber;
        int RandomScriptToRun;

        List <Task> RunQueryTask = new List<Task>();
        Random RandNumber = new Random();

        
        for(int i = 1; i<100;i++)
        {
            //Console.WriteLine(DateTime.Now.ToString());

            RandomDelayInSeconds = RandNumber.Next(1,6);
            RandomDatabaseNumber = RandNumber.Next(1,4);
            RandomScriptToRun = RandNumber.Next(0,7);

            SQLScriptToRun = SQLScript[RandomScriptToRun];

            switch (RandomDatabaseNumber){
                case 1:
                    DatabaseName = "database-v2";
                    ContainerName = "salesOrder";
                    break;
                case 2:
                    DatabaseName = "database-v3";
                    ContainerName = "salesOrder";
                    break;
                default: 
                    DatabaseName = "database-v3";
                    ContainerName = "customer";
                    RandomDatabaseNumber = RandNumber.Next(1,3);
                    if (RandomDatabaseNumber==1)
                        SQLScriptToRun = "SELECT c.firstName, c.lastName, a.zipCode FROM c JOIN a IN c.addresses";
                    else
                        SQLScriptToRun = "SELECT c.firstName, c.lastName, a.zipCode, c.password.salt FROM customer c JOIN a IN c.addresses WHERE a.zipCode >= '70000' and a.zipCode < '80000' AND a.addressLine2 != '' AND (CONTAINS(c.password.salt, '81', true) = true OR CONTAINS(c.password.salt, '84', true) = true)";
                    break;
                    
            }
            QueryDefinition query = new QueryDefinition(SQLScriptToRun);

            Container container = client.GetContainer(DatabaseName, ContainerName);

            try
            {
               RunQueryTask.Add(runSQLScript(ContainerName, container, SQLScriptToRun, query));
            }
            catch
            {
                Console.WriteLine("429 exception");
            }

           // System.Threading.Thread.Sleep(1000*RandomDelayInSeconds); 
           i=10;
        } //while(RandomDelayInSeconds<100);
        
        await Task.WhenAll(RunQueryTask);

    }

    static async Task runSQLScript(string ContainerName, Container container, string SQLScriptToRun, QueryDefinition query)
    {
        if (ContainerName == "customer")
        {
            int customerCounter = 0;
            List<dbcustomer> QueryResults = new List<dbcustomer>();
            using(FeedIterator<dbcustomer> resultSetIterator1 = container.GetItemQueryIterator<dbcustomer>(query))
            {
                while(resultSetIterator1.HasMoreResults)
               {
                    customerCounter++;
                    await resultSetIterator1.ReadNextAsync();
                }
                //Console.WriteLine(customerCounter.ToString());
            }
        } else
        if (ContainerName == "salesOrder")
        {
            int salesOrderCounter = 0;
            List<dbsalesorder> QueryResults = new List<dbsalesorder>();
            using(FeedIterator<dbsalesorder> resultSetIterator = container.GetItemQueryIterator<dbsalesorder>(query))
            {
                while(resultSetIterator.HasMoreResults)
               {
                salesOrderCounter++;
                await resultSetIterator.ReadNextAsync();
               }
            //Console.WriteLine(salesOrderCounter.ToString());
            }
        }
        else Console.WriteLine("No queries");
    }
    internal sealed class dbsalesorder
    {
        public string customerId {get;set;}
    }
    internal sealed class dbcustomer
    {
        public string firstName {get;set;}
        public string lastName {get;set;}
        public string zipCode {get;set;}
    }
}
