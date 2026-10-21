@description('{{title}} of a new Application Insights: a new one, or an existing one of {{group}}.')
param {{name}} string
param {{group}} string = ''

resource {{key}} 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (({{needed}}) && empty({{group}})) {
  name: {{name}}
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

var {{key}}Id = empty({{group}}) ? {{key}}.id : resourceId({{group}}, 'Microsoft.OperationalInsights/workspaces', {{name}})
