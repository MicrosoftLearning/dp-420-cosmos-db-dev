using System;
using Microsoft.Azure.Cosmos;

string connectionString = "<cosmos-connection-string>";

CosmosClient client = new (connectionString);