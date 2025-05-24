﻿using System;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";

string key = "<cosmos-key>";

CosmosClient client = new CosmosClient(endpoint, key);

Database database = await client.CreateDatabaseIfNotExistsAsync("cosmicworks");

Container container = await database.CreateContainerIfNotExistsAsync("products", "/category/name");
