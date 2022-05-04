using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using _28_key_vault.Models;

using Microsoft.Azure.KeyVault;
using Microsoft.Azure.Services.AppAuthentication;

using Microsoft.Azure.Cosmos;
using Newtonsoft.Json;

namespace _28_key_vault.Controllers
{
    public class customerInfo
    { 
        [JsonProperty(PropertyName = "id")]
        public string ID {get;set;} = "";
        public string title {get;set;} = "";
        public string firstName {get;set;} = "";
        public string lastName {get;set;} = "";
        public string emailAddress {get;set;} = "";
        public string phoneNumber {get;set;} = "";
        public string creationDate {get;set;} = "";
    }
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;

        public HomeController(ILogger<HomeController> logger)
        {
            _logger = logger;
        }

        public IActionResult Index()
        {
            string CosmosDBMessage = "Something went wrong, Key Vault secret was not accessible.";

            var (KeyVaultAccessGranted, secret) = GetKeyVaultSecret().GetAwaiter().GetResult();
            
            if (KeyVaultAccessGranted)
            {
                var (CosmosDBM, bool2) = AddCosmosDBDocument(secret).GetAwaiter().GetResult();
                CosmosDBMessage = CosmosDBM;
                secret = "Key Vault Secret = " + secret;
            }
                
            ViewBag.CosmosDBMessage = CosmosDBMessage ;
            ViewBag.KeyVaultSecret = secret;

            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }

        private static async Task<Tuple<string,bool>> AddCosmosDBDocument(string secret)
        {
            string connectionString = secret;

            CosmosClient client = new CosmosClient(connectionString);

            Database GlobalCustomers = await client.CreateDatabaseIfNotExistsAsync("GlobalCustomers");
            Container customers =await GlobalCustomers.CreateContainerIfNotExistsAsync(id: "customers", partitionKeyPath: "/id", throughput: 400);

            customerInfo customer = new customerInfo();

            customer.title = "";
            customer.firstName="Franklin";
            customer.lastName="Ye";
            customer.emailAddress="franklin9@adventure-works.com";
            customer.phoneNumber= "1 (11) 500 555-0139";
            customer.creationDate = "2014-02-05T00:00:00";


            customer.ID = Guid.NewGuid().ToString();
            ItemResponse<customerInfo> response = await customers.CreateItemAsync<customerInfo>(customer, new PartitionKey(customer.ID),
                new ItemRequestOptions()
                {
                    EnableContentResponseOnWrite = false
                });

            if (response.Resource == null)
                return new Tuple<string,bool>( $"\n\nDocuments inserted into the Azure Cosmos DB customer container.",true);
            else
                return new Tuple<string,bool>($"\n\nSomething went wrong, the key vault secret was returned successfully, but no document was created",false);
        }
        
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

    }
}
