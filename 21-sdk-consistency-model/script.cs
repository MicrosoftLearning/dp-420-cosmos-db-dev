using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

using CosmosClient client = new CosmosClient(endpoint, key);

Container container = client.GetContainer("cosmicworks", "products");