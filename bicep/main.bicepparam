using './main.bicep'

// NOTE: Subscription is set via Azure CLI before deployment
// Run: az account set --subscription "your-subscription-id"
// Or use AZURE_SUBSCRIPTION_ID environment variable in deploy.sh

// Basic Configuration
param customerName = 'hcs'
param environment = 'prod'
param location = 'japaneast'   // Azure region

// Storage Account Settings
param storageAccountSku = 'Standard_LRS' // Standard_LRS is cheapest
