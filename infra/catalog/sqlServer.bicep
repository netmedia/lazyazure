@description('{{title}}: a new one (Entra sign-in only, no SQL passwords), or an existing one of {{group}} (used as it is).')
param {{name}} string
param {{group}} string = ''

@description('The Entra admin of a new {{title}} (infra/azure-setup.ps1 asks it): sign-in name, object id, User or Group.')
param {{adminLogin}} string = ''
param {{adminSid}} string = ''
@allowed(['User', 'Group'])
param {{adminType}} string = 'User'

resource {{key}} 'Microsoft.Sql/servers@2023-08-01' = if (empty({{group}})) {
  name: {{name}}
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: {{adminLogin}}
      sid: {{adminSid}}
      principalType: {{adminType}}
      tenantId: subscription().tenantId
    }
  }
}

// The apps reach it from Azure and sign in with their managed identities.
resource {{key}}AzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (empty({{group}})) {
  parent: {{key}}
  name: 'AllowAllWindowsAzureIps'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

var {{key}}Rg = empty({{group}}) ? here : {{group}}
