using System;
using Microsoft.Azure.Cosmos;

string connectionString = "<cosmos-connection-string>";

CosmosClient client = new (connectionString);
    
Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");
Console.WriteLine($"Database:\t{database.Id}");

Container container = await database.CreateContainerIfNotExistsAsync("products", "/categoryId", 400);
Console.WriteLine($"Container:\t{container.Id}");