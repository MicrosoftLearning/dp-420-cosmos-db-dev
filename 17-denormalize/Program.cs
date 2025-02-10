using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Azure.Cosmos;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Microsoft.Extensions.Configuration;
using System.IO;
using System.Net.Http;
using System.Threading;

public class Program
{
    //=================================================================
    //Load secrets
    private static IConfigurationBuilder builder = new ConfigurationBuilder()
        .SetBasePath(Directory.GetCurrentDirectory())
        .AddJsonFile(@"appSettings.json", optional: false, reloadOnChange: true);

    private static IConfigurationRoot config = builder.Build();

    private static readonly string uri = config["uri"];
    private static readonly string key = config["key"];
    private static readonly string gitdatapath = config["gitdatapath"];
    private static readonly CosmosClient client = new CosmosClient(uri, key);

    public static async Task Main(string[] args)
    {

        bool exit = false;

        if (args.Length > 0 && args[0] == "--load-data")
        {
            await GetFilesFromRepo("database-v1");
            await GetFilesFromRepo("database-v2");
            await GetFilesFromRepo("database-v3");
            await GetFilesFromRepo("database-v4");
            await LoadContainersFromFolder(client, "database-v1");
            await LoadContainersFromFolder(client, "database-v2");
            await LoadContainersFromFolder(client, "database-v3");
            await LoadContainersFromFolder(client, "database-v4");

            exit = true;
        }

        while (exit == false)
        {
            Console.Clear();
            Console.WriteLine($"Cosmos DB Modeling and Partitioning");
            Console.WriteLine($"-----------------------------------------");
            Console.WriteLine($"[a]   Start change feed processor");
            Console.WriteLine($"[b]   Update product category name");
            Console.WriteLine($"-----------------------------------------");
            Console.WriteLine($"[c]   Query for customer and all orders");
            Console.WriteLine($"[d]   Create new order and update order total");
            Console.WriteLine($"[e]   Query top 10 customers");
            Console.WriteLine($"[f]   Delete order and update order total");
            Console.WriteLine($"-----------------------------------------");
            Console.WriteLine($"[o]   See other ecommerce operations ");
            Console.WriteLine($"[x]   Exit");

            ConsoleKeyInfo result = Console.ReadKey(true);

            if (result.KeyChar == 'a')
            {
                Console.Clear();
                await StartChangeFeedProcessor();
                Console.WriteLine("press any key to continue");
                var mykey = Console.ReadKey();
            }
            else if (result.KeyChar == 'b')
            {
                Console.Clear();
                await QueryProductsForCategory();
                await UpdateProductCategory();
                await QueryProductsForCategory();
                await RevertProductCategory();
            }
            else if (result.KeyChar == 'c')
            {
                Console.Clear();
                await QueryCustomerAndSalesOrdersByCustomerId();
            }
            else if (result.KeyChar == 'd')
            {
                Console.Clear();
                await CreateNewOrderAndUpdateCustomerOrderTotal();
            }
            else if (result.KeyChar == 'e')
            {
                Console.Clear();
                await GetTop10Customers();
            }
            else if (result.KeyChar == 'f')
            {
                Console.Clear();
                await DeleteOrder();
            }
            else if (result.KeyChar == 'o')
            {
                Console.Clear();
                await BackMenu();
            }
            else if (result.KeyChar == 'x')
            {
                exit = true;
            }
        }
    }

    public static async Task BackMenu()
    {
        bool exit = false;

        while (exit == false)
        {
            Console.Clear();
            Console.WriteLine($"Other E-Commerce Operations");
            Console.WriteLine($"-----------------------------------------");
            Console.WriteLine($"[a]   Query for single customer");
            Console.WriteLine($"[b]   Point read for single customer");
            Console.WriteLine($"[c]   List all product categories");
            Console.WriteLine($"[d]   Query products by category id");
            Console.WriteLine($"-----------------------------------------");
            Console.WriteLine($"[x]   Return to Main Menu");

            ConsoleKeyInfo result = Console.ReadKey(true);

            if (result.KeyChar == 'a')
            {
                Console.Clear();
                await QueryCustomer();
            }
            else if (result.KeyChar == 'b')
            {
                Console.Clear();
                await GetCustomer();
            }
            else if (result.KeyChar == 'c')
            {
                Console.Clear();
                await ListAllProductCategories();
            }
            else if (result.KeyChar == 'd')
            {
                Console.Clear();
                await QueryProductsByCategoryId();
            }
            else if (result.KeyChar == 'o')
            {
                Console.Clear();
                Console.WriteLine(Directory.GetCurrentDirectory());
                Console.WriteLine("press any key to continue");
                var mykey = Console.ReadKey();
            }
            else if (result.KeyChar == 'y')
            {
                Console.Clear();
                await GetFilesFromRepo("database-v1");
                await GetFilesFromRepo("database-v2");
                await GetFilesFromRepo("database-v3");
                await GetFilesFromRepo("database-v4");
                Console.WriteLine("press any key to continue");
                var mykey = Console.ReadKey();

            }
            else if (result.KeyChar == 'z')
            {
                Console.Clear();
                await LoadContainersFromFolder(client, "database-v1");
                await LoadContainersFromFolder(client, "database-v2");
                await LoadContainersFromFolder(client, "database-v3");
                await LoadContainersFromFolder(client, "database-v4");
                Console.WriteLine("press any key to continue");
                var mykey = Console.ReadKey();
            }
            else if (result.KeyChar == 'x')
            {
                exit = true;
            }
        }

    }

    public static async Task QueryCustomer()
    {
        Database database = client.GetDatabase("database-v2");
        Container container = database.GetContainer("customer");

        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";

        //Get a customer with a query
        string sql = $"SELECT * FROM c WHERE c.id = @id";

        FeedIterator<CustomerV2> resultSet = container.GetItemQueryIterator<CustomerV2>(
            new QueryDefinition(sql)
            .WithParameter("@id", customerId),
            requestOptions: new QueryRequestOptions()
            {
                PartitionKey = new PartitionKey(customerId)
            });

        Console.WriteLine("Query for a single customer\n");
        while (resultSet.HasMoreResults)
        {
            FeedResponse<CustomerV2> response = await resultSet.ReadNextAsync();

            foreach (CustomerV2 customer in response)
            {
                Print(customer);
            }

            Console.WriteLine($"Customer Query Request Charge {response.RequestCharge}\n");
            Console.WriteLine("Press any key to continue...");
            Console.ReadKey();
        }
    }

    public static async Task GetCustomer()
    {
        Database database = client.GetDatabase("database-v2");
        Container container = database.GetContainer("customer");

        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";

        Console.WriteLine("Point Read for a single customer\n");

        //Get a customer with a point read
        ItemResponse<CustomerV2> response = await container.ReadItemAsync<CustomerV2>(
            id: customerId,
            partitionKey: new PartitionKey(customerId));

        Print(response.Resource);

        Console.WriteLine($"Point Read Request Charge {response.RequestCharge}\n");
        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task ListAllProductCategories()
    {
        Database database = client.GetDatabase("database-v2");
        Container container = database.GetContainer("productCategory");

        //Get all product categories
        string sql = $"SELECT * FROM c WHERE c.type = 'category'";

        FeedIterator<ProductCategory> resultSet = container.GetItemQueryIterator<ProductCategory>(
            new QueryDefinition(sql),
            requestOptions: new QueryRequestOptions()
            {
                PartitionKey = new PartitionKey("category")
            });

        while (resultSet.HasMoreResults)
        {
            FeedResponse<ProductCategory> response = await resultSet.ReadNextAsync();

            Console.WriteLine("Print out product categories\n");
            foreach (ProductCategory productCategory in response)
            {
                Print(productCategory);
            }
            Console.WriteLine($"Product Category Query Request Charge {response.RequestCharge}\n");
        }
        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task QueryProductsByCategoryId()
    {
        Database database = client.GetDatabase("database-v3");
        Container container = database.GetContainer("product");

        //Category Name = Components, Headsets
        string categoryId = "AB952F9F-5ABA-4251-BC2D-AFF8DF412A4A";

        //Query for products by category id
        string sql = $"SELECT * FROM c WHERE c.categoryId = @categoryId";

        FeedIterator<Product> resultSet = container.GetItemQueryIterator<Product>(
            new QueryDefinition(sql)
            .WithParameter("@categoryId", categoryId),
            requestOptions: new QueryRequestOptions()
            {
                PartitionKey = new PartitionKey(categoryId)
            });

        while (resultSet.HasMoreResults)
        {
            FeedResponse<Product> response = await resultSet.ReadNextAsync();

            Console.WriteLine("Print out products for the passed in category id\n");
            foreach (Product product in response)
            {
                Print(product);
            }
            Console.WriteLine($"Product Query Request Charge {response.RequestCharge}\n");
        }
        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task QueryProductsForCategory()
    {
        Database database = client.GetDatabase("database-v3");
        Container container = database.GetContainer("product");

        //Category Name = Accessories, Tires and Tubes
        string categoryId = "86F3CBAB-97A7-4D01-BABB-ADEFFFAED6B4";

        //Query for this category. How many products?
        string sql = "SELECT COUNT(1) AS ProductCount, c.categoryName " +
            "FROM c WHERE c.categoryId = '86F3CBAB-97A7-4D01-BABB-ADEFFFAED6B4' " +
            "GROUP BY c.categoryName";

        FeedIterator<dynamic> resultSet = container.GetItemQueryIterator<dynamic>(
            new QueryDefinition(sql),
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(categoryId)
            });

        Console.WriteLine("Print out category name and number of products in that category\n");
        while (resultSet.HasMoreResults)
        {
            FeedResponse<dynamic> response = await resultSet.ReadNextAsync();
            foreach (var item in response)
            {
                Console.WriteLine($"Product Count: {item.ProductCount}\nCategory: {item.categoryName}\n");
            }
        }
        Console.WriteLine("Press any key to continue...\n");
        Console.ReadKey();
    }

    public static async Task UpdateProductCategory()
    {
        Database database = client.GetDatabase("database-v3");
        Container container = database.GetContainer("productCategory");

        string categoryId = "86F3CBAB-97A7-4D01-BABB-ADEFFFAED6B4";
        //Category Name = Accessories, Tires and Tubes

        Console.WriteLine("Update the name and replace 'and' with '&'");
        ProductCategory updatedProductCategory = new ProductCategory
        {
            id = categoryId,
            type = "category",
            name = "Accessories, Tires & Tubes"
        };

        await container.ReplaceItemAsync(
            partitionKey: new PartitionKey("category"),
            id: categoryId,
            item: updatedProductCategory);

        Console.WriteLine("Category updated.\nPlease wait...\n");
        Console.ReadKey();
    }

    public static async Task RevertProductCategory()
    {
        Database database = client.GetDatabase("database-v3");
        Container container = database.GetContainer("productCategory");

        string categoryId = "86F3CBAB-97A7-4D01-BABB-ADEFFFAED6B4";
        ProductCategory updatedProductCategory = new ProductCategory
        {
            id = categoryId,
            type = "category",
            name = "Accessories, Tires and Tubes"
        };
        Console.WriteLine("Change category name back to original");

        await container.ReplaceItemAsync(
            partitionKey: new PartitionKey("category"),
            id: categoryId,
            item: updatedProductCategory);

        Console.WriteLine("Category updated.\nPlease wait...\n");
        Console.ReadKey();
    }

    public static async Task QuerySalesOrdersByCustomerId()
    {
        Database database = client.GetDatabase("database-v4");
        Container container = database.GetContainer("customer");
        
        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";

        string sql = "SELECT * from c WHERE c.type = 'salesOrder' and c.customerId = @customerId";

        FeedIterator<SalesOrder> resultSet = container.GetItemQueryIterator<SalesOrder>(
            new QueryDefinition(sql)
            .WithParameter("@customerId", customerId),
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(customerId)
            });

        Console.WriteLine("Print out orders for this customer\n");
        while (resultSet.HasMoreResults)
        {
            FeedResponse<SalesOrder> response = await resultSet.ReadNextAsync();
            foreach (SalesOrder salesOrder in response)
            {
                Print(salesOrder);
            }
        }
        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();

    }

    public static async Task QueryCustomerAndSalesOrdersByCustomerId()
    {
        Database database = client.GetDatabase("database-v4");
        Container container = database.GetContainer("customer");

        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";

        string sql = "SELECT * from c WHERE c.customerId = @customerId";

        FeedIterator<dynamic> resultSet = container.GetItemQueryIterator<dynamic>(
            new QueryDefinition(sql)
            .WithParameter("@customerId", customerId),
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(customerId)
            });

        CustomerV4 customer = new CustomerV4();
        List<SalesOrder> orders = new List<SalesOrder>();

        while (resultSet.HasMoreResults)
        {
            //dynamic response. Deserialize into POCO's based upon "type" property
            FeedResponse<dynamic> response = await resultSet.ReadNextAsync();
            foreach (var item in response)
            {
                if (item.type == "customer")
                {
                    customer = JsonConvert.DeserializeObject<CustomerV4>(item.ToString());

                }
                else if (item.type == "salesOrder")
                {
                    orders.Add(JsonConvert.DeserializeObject<SalesOrder>(item.ToString()));
                }
            }
        }

        Console.ForegroundColor = ConsoleColor.Blue;
        Console.WriteLine("\nPrint out customer record and all their orders");
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine("------------------------------------------------\n");
        Console.ForegroundColor = ConsoleColor.White;

        Print(customer);
        foreach (SalesOrder order in orders)
        {
            Print(order);
        }

        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task CreateNewOrderAndUpdateCustomerOrderTotal()
    {
        Database database = client.GetDatabase("database-v4");
        Container container = database.GetContainer("customer");

        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";
        //Get the customer
        ItemResponse<CustomerV4> response = await container.ReadItemAsync<CustomerV4>(
            id: customerId,
            partitionKey: new PartitionKey(customerId)
            );
        CustomerV4 customer = response.Resource;

        //To-Do: Write code to increment salesorderCount


        //Create a new order
        string orderId = "5350ce31-ea50-4df9-9a48-faff97675ac5"; //Normally would use Guid.NewGuid().ToString()

        SalesOrder salesOrder = new SalesOrder
        {
            id = orderId,
            type = "salesOrder",
            customerId = customer.id,
            orderDate = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            shipDate = "",
            details = new List<SalesOrderDetails>
            {
                new SalesOrderDetails
                {
                    sku = "FR-M94B-38",
                    name = "HL Mountain Frame - Black, 38",
                    price = 1349.6,
                    quantity = 1
                },
                new SalesOrderDetails
                {
                    sku = "SO-R809-M",
                    name = "Racing Socks, M",
                    price = 8.99,
                    quantity = 2
                }
            }
        };

        //To-Do: Write code to insert the new order and update the customer as a transaction
        
        

        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task DeleteOrder()
    {
        Database database = client.GetDatabase("database-v4");
        Container container = database.GetContainer("customer");

        string customerId = "FFD0DD37-1F0E-4E2E-8FAC-EAF45B0E9447";
        string orderId = "5350ce31-ea50-4df9-9a48-faff97675ac5";

        ItemResponse<CustomerV4> response = await container.ReadItemAsync<CustomerV4>(
            id: customerId,
            partitionKey: new PartitionKey(customerId)
        );
        CustomerV4 customer = response.Resource;

        //Decrement the salesOrderTotal property
        customer.salesOrderCount--;

        //Submit both as a transactional batch
        TransactionalBatchResponse txBatchResponse = await container.CreateTransactionalBatch(
            new PartitionKey(customerId))
            .DeleteItem(orderId)
            .ReplaceItem<CustomerV4>(customer.id, customer)
            .ExecuteAsync();

        if (txBatchResponse.IsSuccessStatusCode)
            Console.WriteLine("Order deleted successfully");

        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    public static async Task GetTop10Customers()
    {
        Database database = client.GetDatabase("database-v4");
        Container container = database.GetContainer("customer");

        //Query to get our top 10 customers 
        string sql = "SELECT TOP 10 c.firstName, c.lastName, c.salesOrderCount " +
            "FROM c WHERE c.type = 'customer' " +
            "ORDER BY c.salesOrderCount DESC";

        FeedIterator<dynamic> resultSet = container.GetItemQueryIterator<dynamic>(
            new QueryDefinition(sql));

        Console.WriteLine("Print out top 10 customers and number of orders\n");
        double ru = 0;
        while (resultSet.HasMoreResults)
        {
            FeedResponse<dynamic> response = await resultSet.ReadNextAsync();
            foreach (var item in response)
            {
                Console.WriteLine($"Customer Name: {item.firstName} {item.lastName} \tOrders: {item.salesOrderCount}");
            }
            ru += response.RequestCharge;
        }
        Console.WriteLine($"\nRequest Charge: {ru}\n");

        Console.WriteLine("Press any key to continue...");
        Console.ReadKey();
    }

    static async Task<ChangeFeedProcessor> StartChangeFeedProcessor()
    {
        Console.WriteLine("Building Cosmos DB change feed processor");
        Database database = client.GetDatabase("database-v3");
        Container productCategoryContainer = database.GetContainer("{container to watch}");
        Container productContainer = database.GetContainer("{container to update}");

        ContainerProperties leaseContainerProperties = new ContainerProperties("consoleLeases", "/id");
        Container leaseContainer = await database.CreateContainerIfNotExistsAsync(leaseContainerProperties, throughput: 400);

        var builder = productCategoryContainer.GetChangeFeedProcessorBuilder("ProductCategoryProcessor",
            async (IReadOnlyCollection<ProductCategory> input, CancellationToken cancellationToken) =>
            {
                Console.ForegroundColor = ConsoleColor.Blue;
                Console.WriteLine(" + Change Feed Processor -> " + input.Count + " Change(s) Received");
                Console.ForegroundColor = ConsoleColor.White;

                List<Task> tasks = new List<Task>();

                //To-Do: Write code to capture changed product categories


                await Task.WhenAll(tasks);
            });

        var processor = builder
            .WithInstanceName("ChangeFeedProductCategories")
            .WithLeaseContainer(leaseContainer)
            .Build();

        Console.WriteLine("Starting Cosmos DB change feed processor");


        await processor.StartAsync();
        Console.WriteLine("   change feed processor started!");
        return processor;
    }

    private static async Task UpdateProductCategoryName(Container productContainer, string categoryId, string categoryName)
    {
        //query all products for the category
        string sql = $"SELECT * FROM c WHERE c.categoryId = '{categoryId}'";

        FeedIterator<Product> resultSet = productContainer.GetItemQueryIterator<Product>(
            new QueryDefinition(sql),
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(categoryId)
            });

        int productCount = 0;

        //Loop through all pages
        while (resultSet.HasMoreResults)
        {
            FeedResponse<Product> response = await resultSet.ReadNextAsync();

            //To-Do: Write code to update the product container


            Console.ForegroundColor = ConsoleColor.Blue;
            Console.WriteLine($" + Change Feed Processor ->> Updated {productCount} products with updated category name '{categoryName}'");
            Console.ForegroundColor = ConsoleColor.White;
            Console.Write("Press any key to continue...\n");
        }
    }

    public static void Print(object obj)
    {
        Console.WriteLine($"{JObject.FromObject(obj).ToString()}\n");
    }

    static async Task GetFilesFromRepo(string databaseName)
    {
        string folder = "data" + Path.DirectorySeparatorChar + databaseName;
        string url = gitdatapath + databaseName;
        Console.WriteLine("Geting file info from repo");
        HttpClient httpClient = new HttpClient();
        HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Add("User-Agent", "cosmicworks-samples-client");

        if (!Directory.Exists(folder))
        {
            Directory.CreateDirectory(folder);
        }

        HttpResponseMessage response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            Console.WriteLine("Error reading sample data from GitHub");
            Console.WriteLine($" - {url}");
            return;
        }




        String directoryJson = await response.Content.ReadAsStringAsync(); ;

        GitFileInfo[] dirContents = JsonConvert.DeserializeObject<GitFileInfo[]>(directoryJson);
        var downloadTasks = new List<Task>();

        foreach (GitFileInfo file in dirContents)
        {
            if (file.type == "file")
            {
                Console.WriteLine($"File {file.name} {file.size}");
                var filePath = folder + Path.DirectorySeparatorChar + file.name;


                Boolean downloadFile = true;
                if (File.Exists(filePath))
                {
                    if (new System.IO.FileInfo(filePath).Length == file.size)
                    {
                        Console.WriteLine("    File exists and matches size");
                        downloadFile = false;
                    }
                }

                if (downloadFile)
                {
                    Console.WriteLine($"   Download path {file.download_url}");
                    Console.WriteLine("    Started download...");
                    downloadTasks.Add(HttpGetFile(file.download_url, filePath));
                }
            }
        }

        Task downloadTask = Task.WhenAll(downloadTasks);
        try
        {
            downloadTask.Wait();
        }
        catch
        {

        }

        if (downloadTask.Status == TaskStatus.Faulted)
        {
            Console.WriteLine("Files failed to download");
            foreach (var task in downloadTasks)
            {
                Console.WriteLine("Task {0}: {1}", task.Id, task.Status);
                Console.WriteLine(task.Exception.ToString());
            }
        }
        if (downloadTask.Status == TaskStatus.RanToCompletion) Console.WriteLine("Files download sucessfully");
    }

    static async Task LoadContainersFromFolder(CosmosClient client, string databaseName)
    {
        string folder = "data" + Path.DirectorySeparatorChar + databaseName;
        Database database = client.GetDatabase(databaseName);
        Console.WriteLine("Preparing to load containers");
        string[] fileEntries = Directory.GetFiles(folder);
        List<Task> concurrentLoads = new List<Task>();
        foreach (string fileName in fileEntries)
        {
            var containerName = fileName.Split(Path.DirectorySeparatorChar)[2];
            Console.WriteLine($"    Container {containerName} from {fileName}");
            try
            {
                //ContainerProperties containerProperties = new ContainerProperties(containerName, "/id");
                Container container = database.GetContainer(containerName);
                //    containerProperties: containerProperties,
                //    throughputProperties: ThroughputProperties.CreateAutoscaleThroughput(autoscaleMaxThroughput: 4000)
                //);
                concurrentLoads.Add(LoadContainerFromFile(container, fileName));
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error creating container");
                Console.WriteLine(ex.ToString());
            }
        }
        await Task.WhenAll(concurrentLoads);
    }

    static async Task LoadContainerFromFile(Container container, string file)
    {
        using (StreamReader streamReader = new StreamReader(file))
        {

            int maxDegreeOfParallelismPerWorker = 1500;
            bool usebulk = true;

            string recordsJson = streamReader.ReadToEnd();
            dynamic recordsArray = JsonConvert.DeserializeObject(recordsJson);
            int batches = 0;
            int batchCounter = 0;
            List<Task> concurrentTasks = new List<Task>(maxDegreeOfParallelismPerWorker);
            foreach (var record in recordsArray)
            {
                if (usebulk)
                {
                    concurrentTasks.Add(container.CreateItemAsync(record));
                }
                else
                {
                    container.CreateItemAsync(record);
                }
                batchCounter++;

                if (batchCounter >= maxDegreeOfParallelismPerWorker)
                {
                    batchCounter = 0;
                    await Task.WhenAll(concurrentTasks);
                    Console.WriteLine($"    loading {file} - {batches}");
                    concurrentTasks.Clear();
                    batches++;
                }

            }
            await Task.WhenAll(concurrentTasks);


        }
    }

    static async Task HttpGetFile(string url, string filename)
    {
        using (HttpClient client = new HttpClient())
        {
            using (HttpResponseMessage response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
            using (Stream streamToReadFrom = await response.Content.ReadAsStreamAsync())
            {
                using (Stream streamToWriteTo = File.Open(filename, FileMode.Create))
                {
                    await streamToReadFrom.CopyToAsync(streamToWriteTo);
                }
            }
        }
    }

}
