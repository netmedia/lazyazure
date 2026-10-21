@description('{{title}} (3-24 characters, globally unique; RBAC authorization when existing): a new one, or an existing one of {{group}}.')
param {{name}} string
param {{group}} string = ''

resource {{key}} 'Microsoft.KeyVault/vaults@2023-07-01' = if (empty({{group}})) {
  name: {{name}}
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
  }
}

// The secrets the setup keeps, the apps' read access and yours (to add the secrets put in by hand); a
// module in the vault's resource group, so an existing vault elsewhere works too.
module {{key}}Access 'modules/vault-access.bicep' = {
  name: {{accessName}}
  scope: resourceGroup(empty({{group}}) ? here : {{group}})
  params: {
    vaultName: {{name}}
    readers: {{readers}}
    ownerObjectId: ownerObjectId
    secretValues: {{secretValues}}
    writeSecrets: {{writeSecrets}}
  }
  dependsOn: [{{key}}]
}
