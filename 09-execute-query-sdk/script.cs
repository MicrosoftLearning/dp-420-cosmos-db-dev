using System;
using Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";

string key = "<cosmos-key>";

CosmosClientOptions clientoptions = new CosmosClientOptions()
{
    RequestTimeout = new TimeSpan(0,0,90)
    , OpenTcpConnectionTimeout = new TimeSpan (0,0,90)
};

CosmosClient client = new CosmosClient(endpoint, key, clientoptions);

CosmosDatabase database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");

CosmosContainer container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId");
