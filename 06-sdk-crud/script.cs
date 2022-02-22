using System;
using Microsoft.Azure.Cosmos;

string endpoint = "<cosmos-endpoint>";
string key = "<cosmos-key>";

CosmosClientOptions clientoptions = new CosmosClientOptions()
{
    RequestTimeout = new TimeSpan(0,0,90)
    , OpenTcpConnectionTimeout = new TimeSpan (0,0,90)
};

using CosmosClient client = new CosmosClient(endpoint, key, clientoptions);
