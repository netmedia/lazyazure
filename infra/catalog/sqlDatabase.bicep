@description('{{title}} on {{serverTitle}}.')
param {{name}} string

@description('Size of {{title}}: Basic, S0, S1 (DTU) or GP_S_Gen5_1, GP_S_Gen5_2 (serverless: pauses after an hour without use).')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

// In the server's resource group (a database belongs to its server, also when the server is shared).
module {{key}} 'modules/sql-database.bicep' = {
  name: {{deployName}}
  scope: resourceGroup({{server}}Rg)
  params: {
    serverName: {{serverName}}
    name: {{name}}
    sku: {{size}}
    location: location
    tags: tags
  }
  dependsOn: [{{server}}]
}
