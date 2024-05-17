param keyVaultName string

param clientSecretName string

@secure()
param clientSecretValue string

module searchServiceKVSecret 'core/security/keyvault-secret.bicep' = {
  name: 'clientsecret'
  params: {
    keyVaultName: keyVaultName
    name: clientSecretName
    secretValue: clientSecretValue
  }
}
