targetScope = 'subscription'

// Parameters
param customerName string
param environment string
param location string
param storageAccountSku string
param deploySilverGold bool = false // Flag to deploy Silver/Gold layers

// Variables
var resourceGroupName = 'rg-mustrust-${customerName}-${environment}'
var storageAccountName = 'stmustrust${customerName}${environment}'
var webStorageAccountName = 'stmustrustweb${customerName}${environment}'
var functionAppName = 'func-mustrust-preprocessor-${customerName}-${environment}'
var cosmosAccountName = 'cosmos-mustrust-${customerName}-${environment}'
var analyzerFunctionAppName = 'func-mustrust-analyzer-${customerName}-${environment}'
var languageServiceName = 'lang-mustrust-${customerName}-${environment}'
var translatorAccountName = 'trans-mustrust-${customerName}-${environment}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Environment: environment
    Customer: customerName
    Project: 'MusTrusT'
  }
}

// Storage Account (for Analyzer)
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  scope: rg
  params: {
    name: storageAccountName
    location: location
    sku: storageAccountSku
    functionAppName: ''
  }
}

// Web Storage Account (for Frontend & Preprocessor)
module webStorage 'modules/storage-web.bicep' = {
  name: 'webStorageDeploy'
  scope: rg
  params: {
    name: webStorageAccountName
    location: location
    sku: storageAccountSku
    functionAppName: functionAppName
    enableStaticWebsite: true
  }
}

// Function App (Preprocessor)
module functionApp 'modules/function.bicep' = if (!deploySilverGold) {
  name: 'functionAppDeploy'
  scope: rg
  params: {
    name: functionAppName
    location: location
    storageAccountName: webStorage.outputs.name
    analyzerFunctionAppName: ''
    analyzerFunctionKey: ''
  }
}

// Function App (Preprocessor with Analyzer) - deployed after analyzer is ready
module functionAppWithAnalyzer 'modules/function.bicep' = if (deploySilverGold) {
  name: 'functionAppWithAnalyzerDeploy'
  scope: rg
  params: {
    name: functionAppName
    location: location
    storageAccountName: webStorage.outputs.name
    analyzerFunctionAppName: analyzerFunctionAppName
    analyzerFunctionKey: deploySilverGold ? analyzerFunctionApp.outputs.functionAppDefaultKey : ''
  }
  dependsOn: [analyzerFunctionApp]
}

// Event Grid Subscription (commented out - deploy after code is deployed)
// module eventGrid 'modules/eventgrid.bicep' = {
//   name: 'eventGridDeploy'
//   scope: rg
//   params: {
//     storageAccountName: webStorage.outputs.name
//     functionAppName: functionApp.outputs.name
//     containerName: 'web-input-files'
//   }
// }

// Cosmos DB (Silver & Gold Layers)
module cosmosDb 'modules/cosmos-db.bicep' = if (deploySilverGold) {
  name: 'cosmosDbDeploy'
  scope: rg
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
  scope: rg
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
  scope: rg
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
  scope: rg
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
output resourceGroupName string = rg.name
output storageAccountName string = storage.outputs.name
output storageAccountId string = storage.outputs.id
output webStorageAccountName string = webStorage.outputs.name
output webStorageAccountId string = webStorage.outputs.id
output webStorageWebEndpoint string = webStorage.outputs.webEndpoint
output functionAppName string = deploySilverGold ? functionAppWithAnalyzer.outputs.name : functionApp.outputs.name
output functionAppUrl string = deploySilverGold ? functionAppWithAnalyzer.outputs.url : functionApp.outputs.url

// Silver & Gold Outputs (conditional)
output cosmosAccountName string = deploySilverGold ? cosmosAccountName : 'not-deployed'
output analyzerFunctionAppName string = deploySilverGold ? analyzerFunctionAppName : 'not-deployed'
