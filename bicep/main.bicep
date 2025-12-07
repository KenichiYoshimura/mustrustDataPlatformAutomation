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
var functionAppName = 'func-mustrust-preprocessor-${customerName}-${environment}'
var cosmosAccountName = 'cosmos-mustrust-${customerName}-${environment}'
var analyzerFunctionAppName = 'func-mustrust-analyzer-${customerName}-${environment}'
var languageServiceName = 'lang-mustrust-${customerName}-${environment}'

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

// Storage Account
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  scope: rg
  params: {
    name: storageAccountName
    location: location
    sku: storageAccountSku
    functionAppName: functionAppName
  }
}

// Function App
module functionApp 'modules/function.bicep' = {
  name: 'functionAppDeploy'
  scope: rg
  params: {
    name: functionAppName
    location: location
    storageAccountName: storage.outputs.name
  }
}

// Event Grid Subscription (commented out - deploy after code is deployed)
// module eventGrid 'modules/eventgrid.bicep' = {
//   name: 'eventGridDeploy'
//   scope: rg
//   params: {
//     storageAccountName: storage.outputs.name
//     functionAppName: functionApp.outputs.name
//     containerName: 'bronze-input-files'
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
  ]
}

// Outputs
output resourceGroupName string = rg.name
output storageAccountName string = storage.outputs.name
output storageAccountId string = storage.outputs.id
output functionAppName string = functionApp.outputs.name
output functionAppUrl string = functionApp.outputs.url

// Silver & Gold Outputs (conditional)
output cosmosAccountName string = deploySilverGold ? cosmosAccountName : 'not-deployed'
output analyzerFunctionAppName string = deploySilverGold ? analyzerFunctionAppName : 'not-deployed'
