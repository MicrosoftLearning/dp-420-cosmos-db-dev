using System;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";

string key = "<cosmos-key>";

CosmosClientOptions clientoptions = new CosmosClientOptions()
{
    RequestTimeout = new TimeSpan(0,0,90)
    , OpenTcpConnectionTimeout = new TimeSpan (0,0,90)
};

CosmosClient client = new CosmosClient(endpoint, key, clientoptions);

Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");

Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId");
