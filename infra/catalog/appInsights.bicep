@description('{{title}}: a new one, or an existing one of {{group}} (used as it is).{{optionalNote}}')
param {{name}} string{{nameDefault}}
param {{group}} string = ''

var {{key}}New = {{newExpr}}

resource {{key}} 'Microsoft.Insights/components@2020-02-02' = if ({{key}}New) {
  name: {{nameExpr}}
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: {{workspaceId}}
  }
}

resource {{key}}Existing 'Microsoft.Insights/components@2020-02-02' existing = if ({{existingExpr}}) {
  name: {{nameExpr}}
  scope: resourceGroup(empty({{group}}) ? here : {{group}})
}

var {{key}}Connection = {{key}}New ? {{key}}!.properties.ConnectionString : {{key}}Existing!.properties.ConnectionString
