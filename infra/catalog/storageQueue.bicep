@description('{{title}}: a queue of {{parentTitle}} (3-63 lowercase letters, digits and hyphens).')
param {{name}} string

resource {{key}}Service 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' existing = {
  parent: {{parent}}
  name: 'default'
}

resource {{key}} 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: {{key}}Service
  name: {{name}}
  properties: {}
}
