param name string
param location string = resourceGroup().location
param tags object = {}

param identityName string
param containerAppsEnvironmentName string
param containerRegistryName string
param serviceName string = 'aca'
param exists bool
param openAiDeploymentName string
param openAiEndpoint string
param openAiApiVersion string
param keyVaultName string
param authClientSecretName string
param authClientId string
param authAuthority string
param redisHost string

resource acaIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

module app 'core/host/container-app-upsert.bicep' = {
  name: '${serviceName}-container-app-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityName: acaIdentity.name
    exists: exists
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    env: [
      {
        name: 'AZURE_OPENAI_CHATGPT_DEPLOYMENT'
        value: openAiDeploymentName
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: openAiEndpoint
      }
      {
        name: 'AZURE_OPENAI_API_VERSION'
        value: openAiApiVersion
      }
      {
        name: 'RUNNING_IN_PRODUCTION'
        value: 'true'
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: acaIdentity.properties.clientId
      }
      {
        name: 'AZURE_AUTH_CLIENT_SECRET_NAME'
        value: authClientSecretName
      }
      {
        name: 'AZURE_AUTH_CLIENT_ID'
        value: authClientId
      }
      {
        name: 'AZURE_AUTH_AUTHORITY'
        value: authAuthority
      }
      {
        name: 'AZURE_KEY_VAULT_NAME'
        value: keyVaultName
      }
      {
        name: 'AZURE_REDIS_USER'
        value: acaIdentity.properties.principalId
      }
      {
        name: 'AZURE_REDIS_HOST'
        value: redisHost
      }
    ]
    targetPort: 50505
  }
}

output SERVICE_ACA_IDENTITY_PRINCIPAL_ID string = acaIdentity.properties.principalId
output SERVICE_ACA_NAME string = app.outputs.name
output SERVICE_ACA_URI string = app.outputs.uri
output SERVICE_ACA_IMAGE_NAME string = app.outputs.imageName
