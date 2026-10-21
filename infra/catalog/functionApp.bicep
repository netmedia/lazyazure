@description('{{title}} (globally unique: <name>.azurewebsites.net).')
param {{name}} string
//#if flex

// Where the Flex Consumption app's packages go (a container of {{storageTitle}}).
resource {{key}}Blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: {{storage}}
  name: 'default'
}

resource {{key}}Packages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: {{key}}Blobs
  name: '{{container}}'
  properties: { publicAccess: 'None' }
}
//#end

resource {{key}} 'Microsoft.Web/sites@2024-04-01' = {
  name: {{name}}
  location: location
  kind: 'functionapp,linux'
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: {{hostId}}
    httpsOnly: true
//#if flex
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${{{storage}}.properties.primaryEndpoints.blob}{{container}}'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: { maximumInstanceCount: 40, instanceMemoryMB: 2048 }
      runtime: { name: '{{runtimeName}}', version: '{{runtimeVersion}}' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: {{settingsArray}}
    }
//#end
//#if plan
    siteConfig: {
      linuxFxVersion: '{{runtime}}'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: {{settingsArray}}
    }
//#end
  }
//#if flex
  dependsOn: [{{key}}Packages]
//#end
}

// Deployments come from GitHub Actions with OIDC, so no FTP or basic-auth publishing.
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
