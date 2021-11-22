using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClientOptions options = new () 
{ 
    ApplicationPreferredRegions = new List<string>{ "westus", "eastus" }
};

using CosmosClient client = new(endpoint, key, options);

Container container = client.GetContainer("cosmicworks", "products");

int? currentThroughput = await container.ReadThroughputAsync();

Console.WriteLine($"Current Throughput:\t{currentThroughput}");