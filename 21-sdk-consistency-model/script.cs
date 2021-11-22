using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

using CosmosClient client = new CosmosClient(endpoint, key);

Container container = client.GetContainer("cosmicworks", "products");

var item = new Product("", "Example Product", "");

ItemRequestOptions options = new()
{ 
    ConsistencyLevel = ConsistencyLevel.Eventual 
};

await container.CreateItemAsync<Product>(item, new PartitionKey(""), requestOptions: options);