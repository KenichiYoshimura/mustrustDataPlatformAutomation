using './main.bicep'

// NOTE: Subscription is set via Azure CLI before deployment
// Run: az account set --subscription "your-subscription-id"
// Or use AZURE_SUBSCRIPTION_ID environment variable in deploy.sh

// Basic Configuration
param customerName = 'yys'
param environment = 'dev'
param location = 'japaneast'   // Azure region

// Storage Account Settings
param storageAccountSku = 'Standard_LRS' // Standard_LRS is cheapest

// Silver & Gold Layer Deployment
// Set to true to deploy Cosmos DB and Silver/Gold Function Apps
param deploySilverGold = true

// App Service Preprocessor Deployment (Windows S1 with Easy Auth)
param deployAppServicePreprocessor = true

// Azure AD Configuration for Easy Auth
param aadTenantId = ''
param aadClientId = ''
param aadClientSecret = ''
