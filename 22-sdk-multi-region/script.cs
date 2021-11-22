using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Fluent;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClientBuilder cosmosClientBuilder = new CosmosClientBuilder(endpoint, key)
            .WithApplicationRegion(Regions.EastUS);

using CosmosClient client = cosmosClientBuilder.Build();

Container container = client.GetContainer("cosmicworks", "products");

var item = new Product(Guid.NewGuid().ToString(), "Example Product A", Guid.NewGuid().ToString());

await container.CreateItemAsync<Product>(item);