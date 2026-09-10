metadata description = 'Provisions the Azure Cosmos DB account, databases, and containers for one DP-420 lab profile. setup.ps1 builds every parameter from its own profile table, so this template holds no lab-specific knowledge.'

@description('Name of the Azure Cosmos DB account.')
param accountName string

@description('Primary region for the account.')
param location string

@description('Second region, added at failover priority 1. Empty for every single-region profile.')
param secondaryLocation string = ''

@description('Deploy the account itself. Set false to add databases and containers to an account that already exists, which is what the second stage of the search and agentmemory profiles needs: redeploying an enrolled account would strip the capabilities the learner turned on in the portal.')
param deployAccount bool = true

@description('Create the account in serverless capacity mode.')
param serverless bool = false

@description('Extra account capabilities, such as EnableNoSQLVectorSearch.')
param capabilities array = []

@description('Public network access setting for the account.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Backup mode. Fixed when the account is created and never changeable afterward.')
@allowed([
  'Periodic'
  'Continuous'
])
param backupPolicyType string = 'Periodic'

@description('Retention tier, used only when backupPolicyType is Continuous.')
param continuousTier string = 'Continuous7Days'

@description('Object ID granted the built-in Cosmos DB Data Contributor role. Empty skips the assignment, which the security profile relies on.')
param dataPlanePrincipalId string = ''

@description('Databases to create.')
param databaseNames array = []

@description('''Containers to create, flattened so that no nested loop is needed. Each entry carries:
  databaseName       - the database it belongs to
  name               - the container name
  partitionKeyPaths  - array of one to three paths
  partitionKeyKind   - Hash or MultiHash
  throughput         - manual RU/s, or 0 when the container is autoscale or serverless
  maxThroughput      - autoscale maximum RU/s, or 0 when the container is manual or serverless
  resourceProperties - object merged into the container resource, holding defaultTtl,
                       indexingPolicy, vectorEmbeddingPolicy, and fullTextPolicy when a
                       profile sets them, and empty otherwise''')
param containers array = []

var dataContributorRoleId = '00000000-0000-0000-0000-000000000002'

var accountCapabilities = [for name in (serverless ? union(capabilities, [ 'EnableServerless' ]) : capabilities): {
  name: name
}]

var accountLocations = empty(secondaryLocation) ? [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
] : [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
  {
    locationName: secondaryLocation
    failoverPriority: 1
    isZoneRedundant: false
  }
]

// The resource provider rejects a Periodic policy that carries no interval and
// retention, so the property is omitted altogether and the account keeps the service
// defaults, which is what the profiles that say nothing about backup always got.
var backupPolicy = backupPolicyType == 'Continuous' ? {
  backupPolicy: {
    type: 'Continuous'
    continuousModeProperties: {
      tier: continuousTier
    }
  }
} : {}

resource account 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = if (deployAccount) {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: union({
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: accountLocations
    capabilities: accountCapabilities
    publicNetworkAccess: publicNetworkAccess
    // Every exercise authenticates with the signed-in identity, so no account in this
    // course ever hands out a key or a connection string.
    disableLocalAuth: true
  }, backupPolicy)
}

// Sibling resources carry no dependency on each other, so the deployment creates all of
// them at once. That is the whole reason this template exists: 22 blocking CLI calls
// become one deployment.
// The parent property can't be used here, because the account is conditional and these
// children are not.
resource databases 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-04-15' = [for name in databaseNames: {
  #disable-next-line use-parent-property
  name: '${accountName}/${name}'
  properties: {
    resource: {
      id: name
    }
  }
  dependsOn: [
    account
  ]
}]

resource containerResources 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-04-15' = [for container in containers: {
  name: '${accountName}/${container.databaseName}/${container.name}'
  properties: {
    resource: union({
      id: container.name
      partitionKey: {
        paths: container.partitionKeyPaths
        kind: container.partitionKeyKind
        version: 2
      }
    }, container.resourceProperties)
    options: serverless ? {} : (container.maxThroughput > 0 ? {
      autoscaleSettings: {
        maxThroughput: container.maxThroughput
      }
    } : {
      throughput: container.throughput
    })
  }
  dependsOn: [
    databases
  ]
}]

resource dataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-04-15' = if (!empty(dataPlanePrincipalId)) {
  #disable-next-line use-parent-property
  name: '${accountName}/${guid(accountName, dataPlanePrincipalId, dataContributorRoleId)}'
  properties: {
    roleDefinitionId: resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', accountName, dataContributorRoleId)
    principalId: dataPlanePrincipalId
    scope: resourceId('Microsoft.DocumentDB/databaseAccounts', accountName)
  }
  dependsOn: [
    account
  ]
}
