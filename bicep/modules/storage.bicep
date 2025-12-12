// Simple Storage Account Module
param name string
param location string
param sku string
param functionAppName string = ''
param enableStaticWebsite bool = false

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
    allowBlobPublicAccess: enableStaticWebsite // Enable public access if static website is enabled
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

// Create 3 containers
resource bronzeInputFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'bronze-input-files'
}

resource bronzeProcessedFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'bronze-processed-files'
}

resource bronzeInvalidFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'bronze-invalid-files'
}

// Deployment container for Flex Consumption Function App
resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (functionAppName != '') {
  parent: blobService
  name: functionAppName
}

// Queue Service
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Create queue for file processing (Bronze -> Silver)
resource bronzeFileProcessingQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueService
  name: 'bronze-file-processing-queue'
}

// Create queue for Silver -> Gold enrichment (serial processing)
resource silverGoldProcessingQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueService
  name: 'silver-gold-processing-queue'
}

// Outputs
output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output webEndpoint string = enableStaticWebsite ? storageAccount.properties.primaryEndpoints.web : ''
