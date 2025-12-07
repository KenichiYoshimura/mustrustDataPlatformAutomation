// Azure Language Services (Sentiment Analysis + Translation)
param name string
param location string
param sku string = 'S' // S = Standard

// Tags
param tags object = {}

// Language Service Account
resource languageService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'TextAnalytics'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Outputs
output languageServiceId string = languageService.id
output languageServiceName string = languageService.name
output languageServiceEndpoint string = languageService.properties.endpoint
