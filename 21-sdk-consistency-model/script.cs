using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClient client = new CosmosClient(endpoint, key);

Container container = client.GetContainer("cosmicworks", "products");
