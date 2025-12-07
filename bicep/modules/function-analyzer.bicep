// Azure Function App for Silver, Gold & Report Layers (Combined)
param name string
param location string
param storageAccountName string
param cosmosAccountName string
param cosmosDatabaseName string
param silverContainerName string
param goldContainerName string
param leasesContainerName string
param bronzeQueueName string = 'bronze-file-processing-queue'

// AI Services names (for retrieving keys)
param languageServiceName string

// App Service Plan parameters
param appServicePlanName string = '${name}-plan'
param appServicePlanSku string = 'Y1' // Y1 = Consumption, EP1 = Premium

// Application Insights parameters
param appInsightsName string = '${name}-insights'

// Tags
param tags object = {}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${name}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Storage Account reference (for function app storage)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Cosmos DB Account reference
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

// AI Services references
resource languageService 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: languageServiceName
  scope: resourceGroup()
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: false
  }
}

// Function App (Silver + Gold + Reports)
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      nodeVersion: '~20'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(name)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        // Application Insights
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        // Cosmos DB Settings (All Layers)
        {
          name: 'COSMOS_DB_CONNECTION_STRING'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'COSMOS_DB_DATABASE_NAME'
          value: cosmosDatabaseName
        }
        {
          name: 'COSMOS_DB_SILVER_CONTAINER'
          value: silverContainerName
        }
        {
          name: 'COSMOS_DB_GOLD_CONTAINER'
          value: goldContainerName
        }
        {
          name: 'COSMOS_DB_LEASES_CONTAINER'
          value: leasesContainerName
        }
        // Bronze Layer Settings (Input for Silver)
        {
          name: 'BRONZE_STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'BRONZE_QUEUE_NAME'
          value: bronzeQueueName
        }
        // Document Intelligence (Silver Layer) - Using shared resources
        // Set these manually to point to shared HCS Document Intelligence resource
        {
          name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: '' // To be set manually to shared resource endpoint
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_KEY'
          value: '' // To be set manually to shared resource key
        }
        {
          name: 'BANK_SURVEY_MODEL_ID'
          value: '' // To be set manually after model training
        }
        {
          name: 'WORKSHOP_SURVEY_MODEL_ID'
          value: '' // To be set manually after model training
        }
        // Custom Vision (Silver Layer) - Using shared resources
        // Set these manually to point to shared HCS Custom Vision project
        {
          name: 'CUSTOM_VISION_PREDICTION_ENDPOINT'
          value: '' // To be set manually to shared resource endpoint
        }
        {
          name: 'CUSTOM_VISION_PREDICTION_KEY'
          value: '' // To be set manually to shared resource key
        }
        {
          name: 'CUSTOM_VISION_PROJECT_ID'
          value: '' // To be set manually to shared project ID
        }
        {
          name: 'CUSTOM_VISION_ITERATION_NAME'
          value: 'Iteration6' // Update based on actual iteration name
        }
        // Language Services (Gold Layer)
        {
          name: 'LANGUAGE_SERVICE_ENDPOINT'
          value: languageService.properties.endpoint
        }
        {
          name: 'LANGUAGE_SERVICE_KEY'
          value: languageService.listKeys().key1
        }
        {
          name: 'TRANSLATION_TARGET_LANGUAGE'
          value: 'en'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Outputs
output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output appServicePlanId string = appServicePlan.id
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
