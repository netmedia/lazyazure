@description('{{title}} (globally unique: <name>.servicebus.windows.net); Entra sign-in only, no keys.')
param {{name}} string

@description('Tier of {{title}}: Basic (queues) or Standard (queues and topics).')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

resource {{key}} 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: {{name}}
  location: location
  tags: tags
  sku: { name: {{size}}, tier: {{size}} }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: true // the apps sign in with their managed identities
  }
}
{{queues}}
