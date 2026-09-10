metadata description = 'Optional Microsoft Foundry resource, project, and model deployments for the DP-420 labs. Deploy in the lab resource group through setup.ps1.'

@description('Name of the Foundry resource and its custom subdomain.')
param accountName string

@description('Region with quota for the requested model versions and deployment types.')
param location string

@description('Name of the Foundry project.')
param projectName string = 'dp420'

@description('Signed-in user object ID for Foundry inference and project access.')
param principalId string

@description('Create the account. Set false when setup verifies an existing Foundry resource.')
param deployAccount bool = true

@description('Create the project. Set false when it already exists.')
param deployProject bool = true

@description('Assign Foundry User when the principal does not already hold that role at this scope.')
param deployRoleAssignment bool = true

@description('Create the embedding deployment. Set false when its configuration already matches.')
param deployEmbedding bool = true

@description('Create a chat deployment for memory and RAG labs. False for embedding-only labs or an existing matching deployment.')
param deployChat bool = true

@description('Embedding model used by the exercise.')
@allowed([
  'text-embedding-3-small'
  'text-embedding-3-large'
])
param embeddingModel string = 'text-embedding-3-small'

@description('Embedding model version.')
param embeddingModelVersion string = '1'

@description('Name the SDK passes when requesting embeddings.')
param embeddingDeploymentName string = embeddingModel

@description('Pay-per-token embedding deployment type.')
@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param embeddingDeploymentSku string = 'Standard'

@description('Embedding deployment capacity in model-specific capacity units, not provisioned throughput units.')
@minValue(1)
param embeddingCapacity int = 30

@description('Chat model used by the exercise.')
param chatModel string = 'gpt-5.4-mini'

@description('Chat model version.')
param chatModelVersion string = '2026-03-17'

@description('Name the SDK passes when requesting chat completions.')
param chatDeploymentName string = chatModel

@description('Pay-per-token chat deployment type.')
@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param chatDeploymentSku string = 'GlobalStandard'

@description('Chat deployment capacity in model-specific capacity units, not provisioned throughput units.')
@minValue(1)
param chatCapacity int = 30

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = if (deployAccount) {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    course: 'dp420'
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = if (deployProject) {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'DP-420 labs'
    description: 'Model deployments for Cosmos DB search, retrieval, and memory exercises.'
  }
  dependsOn: [account]
}

resource embedding 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployEmbedding) {
  parent: foundry
  name: embeddingDeploymentName
  sku: {
    name: embeddingDeploymentSku
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModel
      version: embeddingModelVersion
    }
  }
  dependsOn: [account]
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployChat) {
  parent: foundry
  name: chatDeploymentName
  sku: {
    name: chatDeploymentSku
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModel
      version: chatModelVersion
    }
  }
  dependsOn: [account, embedding]
}

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployRoleAssignment) {
  name: guid(foundry.id, principalId, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
    principalId: principalId
    principalType: 'User'
  }
  dependsOn: [account]
}

output foundryAccountName string = foundry.name
output foundryResourceId string = foundry.id
output foundryProjectName string = projectName
output foundryLocation string = location
output embeddingDeployment string = embeddingDeploymentName
output chatDeployment string = chatDeploymentName