// Azure Translator Text Service for multilingual text translation
// Kind: TextTranslation
// SKU: S1 (Standard tier - supports custom subdomains and production workloads)

param translatorAccountName string
param location string
param tags object = {}

// Translator Text API resource
resource translatorAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: translatorAccountName
  location: location
  tags: tags
  kind: 'TextTranslation'
  sku: {
    name: 'S1'
  }
  properties: {
    customSubDomainName: translatorAccountName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Outputs
output accountId string = translatorAccount.id
output accountName string = translatorAccount.name
output endpoint string = translatorAccount.properties.endpoint
output location string = location
@secure()
output primaryKey string = translatorAccount.listKeys().key1
@secure()
output secondaryKey string = translatorAccount.listKeys().key2
