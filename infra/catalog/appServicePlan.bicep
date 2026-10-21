@description('{{title}}: a new one, or an existing one of {{group}} (used as it is).')
param {{name}} string
param {{group}} string = ''

@description('SKU of a new {{title}}: B1 to start, P0v3 for an SLA, autoscale and deployment slots.')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

resource {{key}} 'Microsoft.Web/serverfarms@2024-04-01' = if (empty({{group}})) {
  name: {{name}}
  location: location
  kind: 'linux'
  tags: tags
  sku: { name: {{size}}, tier: startsWith({{size}}, 'P') ? 'PremiumV3' : 'Basic' }
  properties: { reserved: true }
}

var {{key}}Id = empty({{group}}) ? {{key}}.id : resourceId({{group}}, 'Microsoft.Web/serverfarms', {{name}})
