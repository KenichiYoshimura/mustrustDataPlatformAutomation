// Azure App Service Module - Preprocessor (Standard S1, Linux, Node.js 20-lts)
// Purpose: Host Node.js Frontend + API Gateway with Easy Auth integration
// Platform: Linux App Service Standard S1 (supports Easy Auth fully, cost-optimized, modern npm)
// Runtime: Node.js 20-lts LTS (primary), Python 3.11 (system tool for PDF conversion)

param name string
param location string
param storageAccountName string

// Azure AD / Easy Auth parameters
param aadTenantId string
param aadClientId string
@secure()
param aadClientSecret string
param allowedAadGroups string = ''

// Analyzer backend connection (for preprocessor to call analyzer)
param analyzerFunctionAppName string = ''
param analyzerQueueName string = 'bronze-processing'
param analyzerStorageAccountName string = ''
@secure()
param analyzerStorageAccountKey string = ''

// Preprocessor storage (for background upload processing)
param preprocessorStorageAccountName string = ''

// Application Insights parameters
param appInsightsName string = '${name}-insights'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${name}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Managed Identity for secure access to resources
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${name}-identity'
  location: location
}

// App Service Plan - Standard S1 (Linux)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${name}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

// Get storage account reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Get storage account key for connection
var storageKey = storageAccount.listKeys().keys[0].value

// Get preprocessor storage account reference (deployed before this module in main.bicep)
// Only reference if name is provided (not empty string)
resource preprocessorStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: preprocessorStorageAccountName != '' ? preprocessorStorageAccountName : 'dummy-name-will-not-be-used'
}

// Preprocessor storage connection string - only build if storage account name is provided
var preprocessorStorageKey = preprocessorStorageAccountName != '' ? preprocessorStorageAccount.listKeys().keys[0].value : ''
var preprocessorStorageConnectionString = preprocessorStorageAccountName != '' ? 'DefaultEndpointsProtocol=https;AccountName=${preprocessorStorageAccountName};AccountKey=${preprocessorStorageKey};EndpointSuffix=core.windows.net' : ''

// App Service
resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  kind: 'linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: true
      use32BitWorkerProcess: false
      managedPipelineMode: 'Integrated'
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      appCommandLine: 'node server.js'
    }
  }
}

// Application Settings
resource appSettingsResource 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: appService
  name: 'appsettings'
  properties: {
    WEBSITE_NODE_DEFAULT_VERSION: '18.20.3'
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    WEBSITE_LOCAL_CACHE_OPTION: 'Always'
    NODE_ENV: 'production'
    NODE_OPTIONS: '--max-old-space-size=1536'
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
    STORAGE_ACCOUNT_NAME: storageAccountName
    STORAGE_ACCOUNT_KEY: storageKey
    ANALYZER_QUEUE_NAME: analyzerQueueName
    ANALYZER_STORAGE_ACCOUNT_NAME: analyzerStorageAccountName
    ANALYZER_STORAGE_ACCOUNT_KEY: analyzerStorageAccountKey
    ANALYZER_FUNCTION_URL: 'https://${analyzerFunctionAppName}.azurewebsites.net'
    BRONZE_STORAGE_CONNECTION_STRING: preprocessorStorageConnectionString
    AAD_TENANT_ID: aadTenantId
    AAD_CLIENT_ID: aadClientId
    AZURE_AD_CLIENT_SECRET: aadClientSecret
    ALLOWED_AAD_GROUPS: allowedAadGroups
  }
}

// Easy Auth Configuration (authsettingsV2)
// Configured to match dev's working setup: requireAuthentication: true, AllowAnonymous
// This ensures groups claim is properly forwarded through Easy Auth principal
resource easyAuthConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: appService
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'AllowAnonymous'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://${environment().authentication.loginEndpoint}/${aadTenantId}/v2.0'
          clientId: aadClientId
          clientSecretSettingName: 'AZURE_AD_CLIENT_SECRET'
        }
        login: {
          loginParameters: [
            'scope=openid profile email'
          ]
          disableWWWAuthenticate: false
        }
        validation: {
          jwtClaimChecks: {}
          allowedAudiences: [
            aadClientId
          ]
          defaultAuthorizationPolicy: {
            allowedPrincipals: {}
          }
        }
      }
      facebook: {
        enabled: true
        login: {}
        registration: {}
      }
      gitHub: {
        enabled: true
        login: {}
        registration: {}
      }
      google: {
        enabled: true
        login: {}
        registration: {}
        validation: {}
      }
      twitter: {
        enabled: true
        registration: {}
      }
      legacyMicrosoftAccount: {
        enabled: true
        login: {}
        registration: {}
        validation: {}
      }
      apple: {
        enabled: true
        login: {}
        registration: {}
      }
    }
    login: {
      routes: {}
      tokenStore: {
        enabled: true
        tokenRefreshExtensionHours: 72
        fileSystem: {}
        azureBlobStorage: {}
      }
      preserveUrlFragmentsForLogins: false
      allowedExternalRedirectUrls: []
      cookieExpiration: {
        convention: 'FixedTime'
        timeToExpiration: '08:00:00'
      }
      nonce: {
        validateNonce: true
        nonceExpirationInterval: '00:05:00'
      }
    }
    httpSettings: {
      requireHttps: true
      routes: {
        apiPrefix: '/.auth'
      }
      forwardProxy: {
        convention: 'NoProxy'
      }
    }
  }
}

// Web Config for CORS
// Note: Cannot use wildcard '*' with supportCredentials: true
// CORS is handled at SWA level and Easy Auth handles credentials
resource webConfigResource 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: appService
  name: 'web'
  properties: {
    cors: {
      allowedOrigins: [
        '*'
      ]
      supportCredentials: false
    }
  }
}

// Outputs
output appServiceId string = appService.id
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output managedIdentityId string = managedIdentity.id
output appInsightsId string = appInsights.id
