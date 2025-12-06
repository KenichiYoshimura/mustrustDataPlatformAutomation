targetScope = 'subscription'

// Parameters
param customerName string
param environment string
param location string
param storageAccountSku string

// Variables
var resourceGroupName = 'rg-mustrust-${customerName}-${environment}'
var storageAccountName = 'stmustrust${customerName}${environment}'
var functionAppName = 'func-mustrust-preprocessor-${customerName}-${environment}'

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

// Outputs
output resourceGroupName string = rg.name
output storageAccountName string = storage.outputs.name
output storageAccountId string = storage.outputs.id
output functionAppName string = functionApp.outputs.name
output functionAppUrl string = functionApp.outputs.url
