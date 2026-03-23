targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name which is used to generate a short unique hash for each resource')
param name string

@minLength(1)
@description('Location for the OpenAI resource')
// https://learn.microsoft.com/azure/ai-services/openai/concepts/models?tabs=python-secure%2Cglobal-standard%2Cstandard-chat-completions#models-by-deployment-type
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'norwayeast'
  'polandcentral'
  'southafricanorth'
  'southcentralus'
  'southindia'
  'spaincentral'
  'swedencentral'
  'switzerlandnorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('Name of the GPT model to deploy')
param gptModelName string = 'gpt-5.2-chat'

@description('Version of the GPT model to deploy')
// See version availability in this table:
// https://learn.microsoft.com/azure/ai-services/openai/concepts/models?tabs=python-secure%2Cglobal-standard%2Cstandard-chat-completions#models-by-deployment-type
param gptModelVersion string = '2026-02-10'

@description('Name of the model deployment (can be different from the model name)')
param gptDeploymentName string = 'gpt-5.2-chat'

@description('Capacity of the GPT deployment')
// You can increase this, but capacity is limited per model/region, so you will get errors if you go over
// https://learn.microsoft.com/en-us/azure/ai-services/openai/quotas-limits
param gptDeploymentCapacity int = 30

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Flag to decide where to create RBAC roles for current user')
param createRoleForUser bool = true

param acaExists bool = false

param openAiResourceGroupName string = ''

param authTenantId string
param authClientId string = ''
@secure()
param authClientSecret string = ''
param authClientSecretName string = 'AZURE-AUTH-CLIENT-SECRET'

param runningOnGh bool = false

var resourceToken = toLower(uniqueString(subscription().id, name, location))
var tags = { 'azd-env-name': name }

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${name}-rg'
  location: location
  tags: tags
}

resource openAiResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(openAiResourceGroupName)) {
  name: !empty(openAiResourceGroupName) ? openAiResourceGroupName : resourceGroup.name
}

var prefix = '${name}-${resourceToken}'

var openAiServiceName = '${prefix}-openai'
module openAi 'br/public:avm/res/cognitive-services/account:0.7.1' = {
  name: 'openai'
  scope: resourceGroup
  params: {
    name: openAiServiceName
    location: location
    tags: tags
    kind: 'OpenAI'
    sku: 'S0'
    customSubDomainName: openAiServiceName
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    deployments: [
      {
        name: gptDeploymentName
        model: {
          format: 'OpenAI'
          name: gptModelName
          version: gptModelVersion
        }
        sku: {
          name: 'GlobalStandard'
          capacity: gptDeploymentCapacity
        }
      }
    ]
    roleAssignments: createRoleForUser ? [
      {
        principalId: principalId
        roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
        principalType: 'User'
      }
    ] : []
  }
}

module logAnalyticsWorkspace 'core/monitor/loganalytics.bicep' = {
  name: 'loganalytics'
  scope: resourceGroup
  params: {
    name: '${prefix}-loganalytics'
    location: location
    tags: tags
  }
}

module redisCache 'core/cache/redis.bicep' = {
  name: 'redis'
  scope: resourceGroup
  params: {
    name: '${prefix}-redis'
    location: location
    tags: tags
  }
}

module redisAccessBackend 'core/cache/redis-access.bicep' = {
  name: 'redis-access-for-backend'
  scope: resourceGroup
  params: {
    redisCacheName: redisCache.outputs.name
    principalId: aca.outputs.SERVICE_ACA_IDENTITY_PRINCIPAL_ID
    accessPolicyAlias: 'Backend'
  }
}

module redisBackendUser 'core/cache/redis-access.bicep' = if (createRoleForUser) {
  name: 'redis-access-for-user'
  scope: resourceGroup
  params: {
    redisCacheName: redisCache.outputs.name
    principalId: principalId
    accessPolicyAlias: 'User'
  }
}

module redisDiagnostics 'core/cache/redis-diagnostics.bicep' = {
  name: 'redis-diagnostics'
  scope: resourceGroup
  params: {
    cacheName: redisCache.outputs.name
    diagnosticWorkspaceId: logAnalyticsWorkspace.outputs.id
  }
}

// Container apps host (including container registry)
module containerApps 'core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: resourceGroup
  params: {
    name: 'app'
    location: location
    tags: tags
    containerAppsEnvironmentName: '${prefix}-containerapps-env'
    containerRegistryName: '${replace(prefix, '-', '')}registry'
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.outputs.name
  }
}

// Container app frontend
var authAuthority = '${environment().authentication.loginEndpoint}${authTenantId}'
module aca 'aca.bicep' = {
  name: 'aca'
  scope: resourceGroup
  params: {
    name: replace('${take(prefix,19)}-ca', '--', '-')
    location: location
    tags: tags
    identityName: '${prefix}-id-aca'
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    openAiDeploymentName: gptDeploymentName
    openAiEndpoint: openAi.outputs.endpoint
    keyVaultName: keyVault.outputs.name
    authClientId: authClientId
    authClientSecretName: authClientSecretName
    authAuthority: authAuthority
    redisHost: redisCache.outputs.hostName
    exists: acaExists
  }
}

module openAiRoleUser 'core/security/role.bicep' = if (createRoleForUser) {
  scope: openAiResourceGroup
  name: 'openai-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'User'
  }
}

module openAiRoleBackend 'core/security/role.bicep' = {
  scope: openAiResourceGroup
  name: 'openai-role-backend'
  params: {
    principalId: aca.outputs.SERVICE_ACA_IDENTITY_PRINCIPAL_ID
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

module keyVault 'core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: resourceGroup
  params: {
    name: '${replace(take(prefix, 17), '-', '')}-vault'
    location: location
  }
}

module userKeyVaultAccess 'core/security/role.bicep' = {
  name: 'user-keyvault-access'
  scope: resourceGroup
  params: {
    principalId: principalId
    principalType: runningOnGh ? 'ServicePrincipal' : 'User'
    roleDefinitionId: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  }
}

module webKeyVaultAccess 'core/security/role.bicep' = {
  name: 'web-keyvault-access'
  scope: resourceGroup
  params: {
    principalId:  aca.outputs.SERVICE_ACA_IDENTITY_PRINCIPAL_ID
    principalType: 'ServicePrincipal'
    roleDefinitionId: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  }
}

module secrets 'secrets.bicep' = if (!empty(authClientSecret)) {
  name: 'secrets'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    clientSecretName: authClientSecretName
    clientSecretValue: authClientSecret
  }
}

output AZURE_LOCATION string = location

output AZURE_OPENAI_CHATGPT_DEPLOYMENT string = gptDeploymentName
output AZURE_OPENAI_ENDPOINT string = openAi.outputs.endpoint
output AZURE_OPENAI_RESOURCE string = openAi.outputs.name
output AZURE_OPENAI_RESOURCE_GROUP string = openAiResourceGroup.name
output AZURE_OPENAI_RESOURCE_GROUP_LOCATION string = openAiResourceGroup.location

output SERVICE_ACA_IDENTITY_PRINCIPAL_ID string = aca.outputs.SERVICE_ACA_IDENTITY_PRINCIPAL_ID
output SERVICE_ACA_NAME string = aca.outputs.SERVICE_ACA_NAME
output SERVICE_ACA_URI string = aca.outputs.SERVICE_ACA_URI
output SERVICE_ACA_IMAGE_NAME string = aca.outputs.SERVICE_ACA_IMAGE_NAME
output AZURE_AUTH_REDIRECT_URI string = '${aca.outputs.SERVICE_ACA_URI}/redirect'
output AZURE_AUTH_CLIENT_SECRET_NAME string = authClientSecretName
output AZURE_AUTH_CLIENT_ID string = authClientId
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_AUTH_AUTHORITY string = authAuthority

output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName

output AZURE_REDIS_HOST string = redisCache.outputs.hostName
