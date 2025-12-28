targetScope = 'resourceGroup'

// Parameters
param customerName string
param environment string
param location string
param storageAccountSku string
param deploySilverGold bool = false // Flag to deploy Silver/Gold layers

// App Service Preprocessor parameters (Linux S1)
param deployAppServicePreprocessor bool = false // Flag to deploy new App Service Standard S1 Preprocessor
param aadTenantId string = '' // Azure AD tenant ID for Easy Auth
param aadClientId string = '' // Azure AD app client ID for Easy Auth
@secure()
param aadClientSecret string = '' // Azure AD app client secret for Easy Auth
param allowedAadGroups string = '' // Comma-separated Azure AD group object IDs for access control

// Variables
var storageAccountName = 'stmustrust${customerName}${environment}'
var webStorageAccountName = 'stmustrustweb${customerName}${environment}'
var functionAppName = 'func-mustrust-preprocessor-${customerName}-${environment}'
var appServicePreprocessorName = 'app-mustrust-preprocessor-${customerName}-${environment}' // New App Service (Linux S1)
var cosmosAccountName = 'cosmos-mustrust-${customerName}-${environment}'
var analyzerFunctionAppName = 'func-mustrust-analyzer-${customerName}-${environment}'
var languageServiceName = 'lang-mustrust-${customerName}-${environment}'
var translatorAccountName = 'trans-mustrust-${customerName}-${environment}'

// Storage Account (for Analyzer)
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  params: {
    name: storageAccountName
    location: location
    sku: storageAccountSku
    functionAppName: ''
  }
}

// Web Storage Account (for Frontend & Preprocessor)
// Includes: static website, file uploads, preprocessor staging, and processing queue
module webStorage 'modules/storage-web.bicep' = {
  name: 'webStorageDeploy'
  params: {
    name: webStorageAccountName
    location: location
    sku: storageAccountSku
    functionAppName: functionAppName
    enableStaticWebsite: true
  }
}

// NOTE: Function App for Preprocessor has been removed.
// Using App Service S1 (Windows) instead per migration plan.
// See PREPROCESSOR_MIGRATION.md for details on why Easy Auth requires App Service.

// App Service Standard S1 (Linux) - NEW Preprocessor Platform
// Uses web storage for all operations (frontend + preprocessor staging)
module appServicePreprocessor 'modules/app-service-preprocessor.bicep' = if (deployAppServicePreprocessor) {
  name: 'appServicePreprocessorDeploy'
  params: {
    name: appServicePreprocessorName
    location: location
    storageAccountName: webStorage.outputs.name
    aadTenantId: aadTenantId
    aadClientId: aadClientId
    aadClientSecret: aadClientSecret
    analyzerFunctionAppName: analyzerFunctionAppName
    analyzerQueueName: 'bronze-processing'
    analyzerStorageAccountName: storageAccountName
    analyzerStorageAccountKey: storage.outputs.accountKey
    appInsightsName: '${appServicePreprocessorName}-insights'
    allowedAadGroups: allowedAadGroups
  }
}

// Cosmos DB (Silver & Gold Layers)
module cosmosDb 'modules/cosmos-db.bicep' = if (deploySilverGold) {
  name: 'cosmosDbDeploy'
  params: {
    cosmosAccountName: cosmosAccountName
    location: location
    databaseName: 'mustrustDataPlatform'
    silverContainerName: 'silver-extracted-documents'
    goldContainerName: 'gold-enriched-documents'
    leasesContainerName: 'leases'
    tags: {
      Environment: environment
      Customer: customerName
      Project: 'MusTrusT'
    }
  }
}

// Language Services (Sentiment + Translation)
module languageService 'modules/language-services.bicep' = if (deploySilverGold) {
  name: 'languageServiceDeploy'
  params: {
    name: languageServiceName
    location: location
    sku: 'S'
    tags: {
      Environment: environment
      Customer: customerName
      Project: 'MusTrusT'
    }
  }
}

// Translator Text Service
module translator 'modules/translator.bicep' = if (deploySilverGold) {
  name: 'translatorDeploy'
  params: {
    translatorAccountName: translatorAccountName
    location: location
    tags: {
      Environment: environment
      Customer: customerName
      Project: 'MusTrusT'
    }
  }
}

// Analyzer Function App (Silver + Gold + Reports - All in One)
module analyzerFunctionApp 'modules/function-analyzer.bicep' = if (deploySilverGold) {
  name: 'analyzerFunctionAppDeploy'
  params: {
    name: analyzerFunctionAppName
    location: location
    storageAccountName: storage.outputs.name
    cosmosAccountName: cosmosAccountName
    cosmosDatabaseName: 'mustrustDataPlatform'
    silverContainerName: 'silver-extracted-documents'
    goldContainerName: 'gold-enriched-documents'
    leasesContainerName: 'leases'
    bronzeQueueName: 'bronze-file-processing-queue'
    languageServiceName: languageServiceName
    tags: {
      Environment: environment
      Customer: customerName
      Project: 'MusTrusT'
      Layer: 'Analyzer'
    }
  }
  dependsOn: [
    cosmosDb
    languageService
    translator
  ]
}

// Outputs
output storageAccountName string = storage.outputs.name
output storageAccountId string = storage.outputs.id
output webStorageAccountName string = webStorage.outputs.name
output webStorageAccountId string = webStorage.outputs.id
output webStorageWebEndpoint string = webStorage.outputs.webEndpoint

// Note: App Service and Function App outputs available in Azure Portal
// - App Service Name: app-mustrust-preprocessor-{customer}-{environment}
// - Resource Group: rg-mustrust-{customer}-{environment}
// Storage Consolidation: Web storage now includes frontend + preprocessor (2 accounts total)
