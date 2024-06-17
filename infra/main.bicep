targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name which is used to generate a short unique hash for each resource')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Flag to decide where to create RBAC roles for current user')
param createRoleForUser bool = true

param acaExists bool = false

param openAiResourceName string = ''
param openAiResourceGroupName string = ''
param openAiResourceGroupLocation string = ''
param openAiSkuName string = ''
param openAiDeploymentCapacity int = 30
param openAiApiVersion string = ''

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

resource openAiResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing =
  if (!empty(openAiResourceGroupName)) {
    name: !empty(openAiResourceGroupName) ? openAiResourceGroupName : resourceGroup.name
  }

var prefix = '${name}-${resourceToken}'

var openAiDeploymentName = 'chatgpt'
module openAi 'core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: openAiResourceGroup
  params: {
    name: !empty(openAiResourceName) ? openAiResourceName : '${resourceToken}-cog'
    location: !empty(openAiResourceGroupLocation) ? openAiResourceGroupLocation : location
    tags: tags
    sku: {
      name: !empty(openAiSkuName) ? openAiSkuName : 'S0'
    }
    deployments: [
      {
        name: openAiDeploymentName
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0613'
        }
        sku: {
          name: 'Standard'
          capacity: openAiDeploymentCapacity
        }
      }
    ]
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
    openAiDeploymentName: openAiDeploymentName
    openAiEndpoint: openAi.outputs.endpoint
    openAiApiVersion: openAiApiVersion
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
    principalId: runningOnGh ? '' : principalId
  }
}

module userKVAccess 'core/security/keyvault-access.bicep' = if (!runningOnGh) {
  name: 'user-keyvault-access'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
  }
}

module webKVAccess 'core/security/keyvault-access.bicep' = {
  name: 'web-keyvault-access'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: aca.outputs.SERVICE_ACA_IDENTITY_PRINCIPAL_ID
  }
}

module secrets 'secrets.bicep' =
  if (!empty(authClientSecret)) {
    name: 'secrets'
    scope: resourceGroup
    params: {
      keyVaultName: keyVault.outputs.name
      clientSecretName: authClientSecretName
      clientSecretValue: authClientSecret
    }
  }

output AZURE_LOCATION string = location

output AZURE_OPENAI_CHATGPT_DEPLOYMENT string = openAiDeploymentName
output AZURE_OPENAI_API_VERSION string = openAiApiVersion
output AZURE_OPENAI_ENDPOINT string = openAi.outputs.endpoint
output AZURE_OPENAI_RESOURCE string = openAi.outputs.name
output AZURE_OPENAI_RESOURCE_GROUP string = openAiResourceGroup.name
output AZURE_OPENAI_SKU_NAME string = openAi.outputs.skuName
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
