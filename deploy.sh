#!/bin/bash

# Simple Storage Deployment Script
set -e

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --subscription)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./deploy.sh [--subscription SUB_ID]"
      exit 1
      ;;
  esac
done

# Fall back to environment variable
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID:-}}"

echo "🚀 MusTrusT Storage Deployment"
echo "==============================="
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
  echo "❌ Azure CLI not installed. Install from: https://aka.ms/azure-cli"
  exit 1
fi

# Check login
if ! az account show &> /dev/null; then
  echo "❌ Not logged in. Run: az login"
  exit 1
fi

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
  echo "📌 Setting subscription to: $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

echo "✅ Logged in as: $(az account show --query user.name -o tsv)"
echo "✅ Subscription: $(az account show --query name -o tsv)"
echo ""
echo "📝 Using parameters from: bicep/main.bicepparam"
echo ""

# Derive deployment parameters from bicepparam written by setup-environment.sh
if [ ! -f "bicep/main.bicepparam" ]; then
  echo "❌ bicep/main.bicepparam not found. Run setup-environment.sh first."
  exit 1
fi

# Extract single-quoted values safely (ignore trailing comments)
CUSTOMER_NAME=$(grep -E "^param[[:space:]]+customerName[[:space:]]*=" bicep/main.bicepparam | sed -E "s/.*= '([^']*)'.*/\1/")
ENVIRONMENT=$(grep -E "^param[[:space:]]+environment[[:space:]]*=" bicep/main.bicepparam | sed -E "s/.*= '([^']*)'.*/\1/")
LOCATION=$(grep -E "^param[[:space:]]+location[[:space:]]*=" bicep/main.bicepparam | sed -E "s/.*= '([^']*)'.*/\1/")

if [ -z "$CUSTOMER_NAME" ] || [ -z "$ENVIRONMENT" ]; then
  echo "❌ Could not read customerName/environment from bicep/main.bicepparam"
  exit 1
fi

RESOURCE_GROUP="rg-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
LOCATION=${LOCATION:-japaneast}
LOCATION=$(echo "$LOCATION" | tr -d '[:space:]')

# Create resource group first (idempotent)
echo "📦 Creating resource group: $RESOURCE_GROUP ($LOCATION)"
if ! az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none 2>/dev/null; then
  echo "❌ Failed to create resource group. Location parsed as '$LOCATION'."
  echo "   Ensure location in bicep/main.bicepparam is a valid Azure region (e.g., 'japaneast')."
  exit 1
fi

# Deploy to resource group scope
echo "📦 Deploying infrastructure..."
az deployment group create \
    --name "mustrust-deploy-$(date +%Y%m%d-%H%M%S)" \
  --resource-group "$RESOURCE_GROUP" \
    --template-file bicep/main.bicep \
    --parameters bicep/main.bicepparam

DEPLOYMENT_EXIT_CODE=$?

if [ $DEPLOYMENT_EXIT_CODE -ne 0 ]; then
    echo "❌ Deployment failed"
    echo ""
    echo "Common issues:"
    echo "  • Soft-deleted Cosmos DB: Check for soft-deleted Cosmos DB accounts"
    echo "    - List: az rest --method get --uri 'https://management.azure.com/subscriptions/\${SUBSCRIPTION_ID}/providers/Microsoft.DocumentDB/deletedAccounts?api-version=2023-04-15'"
    echo "    - Purge: Use cleanup-environment.sh script with --customer and --environment flags"
    echo "  • Soft-deleted Cognitive Services: Check for soft-deleted resources"
    echo "    - Run: az cognitiveservices account list-deleted"
    echo "    - Purge: az cognitiveservices account purge --name <name> --resource-group <rg> --location <location>"
    echo "  • Resource conflicts: A resource with the same name may already exist"
    echo "  • Permission issues: Ensure you have Contributor access to the subscription"
    echo ""
    exit 1
fi

# Show results
echo ""
echo "✅ Deployment Complete!"
echo "======================="
echo ""
