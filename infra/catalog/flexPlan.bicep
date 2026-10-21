@description('{{title}}: Flex Consumption (functions billed per use).')
param {{name}} string

resource {{key}} 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: {{name}}
  location: location
  kind: 'functionapp'
  tags: tags
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

var {{key}}Id = {{key}}.id
