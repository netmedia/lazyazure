@description('{{title}} (deployed by GitHub Actions with its deployment token).')
param {{name}} string

@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

resource {{key}} 'Microsoft.Web/staticSites@2024-04-01' = {
  name: {{name}}
  location: staticLocation
  tags: tags
  sku: { name: {{size}}, tier: {{size}} }
  properties: {}
}
//#if settings

// The settings of its managed functions.
resource {{key}}Settings 'Microsoft.Web/staticSites/config@2024-04-01' = {
  parent: {{key}}
  name: 'appsettings'
  properties: {{settingsObject}}
}
//#end
