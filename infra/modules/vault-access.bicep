// The Key Vault part of main.bicep (infra/catalog/keyVault.bicep), deployed in the vault's resource group
// (so an existing vault elsewhere works too): the secrets the setup keeps, Key Vault Secrets User for each
// app that reads them and, when given, Key Vault Secrets Officer for the person running the setup (to add
// the secrets put in by hand).

param vaultName string

@description('The apps that read the secrets: [{ id, principalId }] (their managed identities).')
param readers array = []

param ownerObjectId string = ''

@description('The secrets the setup keeps, by name.')
@secure()
param secretValues object = {}

@description('The secrets to write: only new or changed ones, as every write is a new version.')
param writeSecrets array = []

var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for name in writeSecrets: {
  parent: vault
  name: name
  properties: { value: secretValues[name] }
}]

resource appsReadSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for reader in readers: {
  scope: vault
  name: guid(vault.id, reader.id, keyVaultSecretsUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: reader.principalId
    principalType: 'ServicePrincipal'
  }
}]

resource ownerManagesSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ownerObjectId)) {
  scope: vault
  name: guid(vault.id, ownerObjectId, keyVaultSecretsOfficer)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficer)
    principalId: ownerObjectId
    principalType: 'User'
  }
}
