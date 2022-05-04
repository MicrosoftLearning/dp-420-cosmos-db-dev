using Microsoft.Azure.Cosmos;
using static Microsoft.Azure.Cosmos.Container;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClient client = new CosmosClient(endpoint, key);
