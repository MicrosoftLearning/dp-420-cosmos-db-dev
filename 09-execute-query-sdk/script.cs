using System;
using Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";

string key = "<cosmos-key>";

CosmosClient client = new CosmosClient(endpoint, key);

CosmosDatabase database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");

CosmosContainer container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId");
