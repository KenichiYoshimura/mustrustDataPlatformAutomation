// Web Storage Account Module for Frontend & Preprocessor
param name string
param location string
param sku string
param functionAppName string = ''
param enableStaticWebsite bool = true

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: enableStaticWebsite // Enable public access for static website
  }
}

// Blob Service with Static Website Configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: enableStaticWebsite ? {
    isVersioningEnabled: false
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'HEAD'
            'OPTIONS'
            'POST'
            'PUT'
          ]
          allowedHeaders: [
            '*'
          ]
          exposedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 3600
        }
      ]
    }
  } : {}
}

// Web Input Files Container - where frontend uploads files
resource webInputFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'web-input-files'
}

// Deployment container for Flex Consumption Function App
resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (functionAppName != '') {
  parent: blobService
  name: functionAppName
}

// Outputs
output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output webEndpoint string = enableStaticWebsite ? storageAccount.properties.primaryEndpoints.web : ''
