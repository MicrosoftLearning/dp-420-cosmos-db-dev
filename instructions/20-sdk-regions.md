---
lab:
    title: 'Connect to different regions with the Azure Cosmos DB SQL API SDK'
    module: 'Module 9 - Design and implement a replication strategy for Azure Cosmos DB SQL API'
---

# Connect to different regions with the Azure Cosmos DB SQL API SDK

When you enable geo-redundancy for an Azure Cosmos DB SQL API account, you can then use the SDK to read data from regions in any order you configure. This technique is beneficial when you distribute your read requests across all of your available read regions.

In this lab, you will configure the CosmosClient class to connect to read regions in a fallback order that you manually configure.
