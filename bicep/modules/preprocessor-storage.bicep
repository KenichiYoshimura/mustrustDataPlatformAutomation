/**
 * Bicep Template: Preprocessor Upload Feature Infrastructure
 * 
 * Creates:
 * - Storage account for preprocessor blob and queue
 * - Containers: preprocessor-uploads, preprocessor-processing
 * - Queue: preprocessor-file-processing-queue
 * - Role assignment for App Service to access storage
 */

// ============================================================================
// Parameters
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the preprocessor storage account (must be globally unique)')
param preprocessorStorageAccountName string

@description('SKU for storage account')
param storageAccountSku string = 'Standard_LRS'

@description('Name of the processing queue')
param processingQueueName string = 'preprocessor-file-processing-queue'

// ============================================================================
// Variables
// ============================================================================

var containerNames = [
  'preprocessor-uploads'
  'preprocessor-processing'
]

// ============================================================================
// Resources
// ============================================================================

// Storage Account
resource preprocessorStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: preprocessorStorageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob Services
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: preprocessorStorage
  name: 'default'
}

// Containers
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [
  for containerName in containerNames: {
    parent: blobServices
    name: containerName
    properties: {
      publicAccess: 'None'
    }
  }
]

// Queue Services
resource queueServices 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: preprocessorStorage
  name: 'default'
}

// Processing Queue
resource processingQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueServices
  name: processingQueueName
  properties: {
    metadata: {}
  }
}

// NOTE: RBAC role assignments removed to avoid circular dependency
// App Service will use connection string authentication via BRONZE_STORAGE_CONNECTION_STRING
// For production, consider adding RBAC in a separate deployment pass or using Managed Identity with delayed assignment

// ============================================================================
// Outputs
// ============================================================================

@description('Storage account name')
output storageAccountName string = preprocessorStorage.name

@description('Storage account resource ID')
output storageAccountId string = preprocessorStorage.id

@secure()
@description('Primary storage key (for connection string)')
output storageAccountKey string = preprocessorStorage.listKeys().keys[0].value

@secure()
@description('Connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${preprocessorStorage.name};AccountKey=${preprocessorStorage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

@description('Blob endpoint URI')
output blobEndpoint string = preprocessorStorage.properties.primaryEndpoints.blob

@description('Queue endpoint URI')
output queueEndpoint string = preprocessorStorage.properties.primaryEndpoints.queue

@description('Processing queue name')
output processingQueueName string = processingQueueName
