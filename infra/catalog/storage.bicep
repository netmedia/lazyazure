@description('{{title}} (3-24 lowercase letters and digits, globally unique).')
param {{name}} string

resource {{key}} 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: {{name}}
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // the apps sign in with their managed identities
    defaultToOAuthAuthentication: true
  }
}
