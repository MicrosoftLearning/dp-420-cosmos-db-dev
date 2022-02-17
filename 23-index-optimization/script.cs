using System.Text.Json;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClientOptions clientoptions = new CosmosClientOptions()
{
    RequestTimeout = new TimeSpan(0,0,90)
    , OpenTcpConnectionTimeout = new TimeSpan (0,0,90)
};

CosmosClient client = new CosmosClient(endpoint, key, clientoptions);

Container container = client.GetContainer("cosmicworks", "products");

string json = await File.ReadAllTextAsync("sample.json");

json = json.Replace(
    "<unique-identifier>", 
    $"{Guid.NewGuid()}"
);

Product? item = JsonSerializer.Deserialize<Product>(json);

if (item is not null)
{
    var response = await container.UpsertItemAsync<Product>(item);

    Console.WriteLine($"Item Created:\t{response.Resource.id}");
    Console.WriteLine($"RU Charge:\t{response.RequestCharge:0.00}");
}
