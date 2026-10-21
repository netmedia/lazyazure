@description('{{title}} (globally unique: <name>.azurewebsites.net).')
param {{name}} string

resource {{key}} 'Microsoft.Web/sites@2024-04-01' = {
  name: {{name}}
  location: location
  kind: 'app,linux'
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: {{hostId}}
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: '{{runtime}}'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
//#if health
      healthCheckPath: '{{healthCheckPath}}'
//#end
      appSettings: {{settingsArray}}
    }
  }
}

// Deployments come from GitHub Actions with OIDC (infra/README.md), so no FTP or basic-auth publishing.
resource {{key}}Ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: {{key}}
  name: 'ftp'
  properties: { allow: false }
}

resource {{key}}Scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: {{key}}
  name: 'scm'
  properties: { allow: false }
}
