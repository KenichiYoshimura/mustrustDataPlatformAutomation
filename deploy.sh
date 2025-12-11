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

# Deploy
echo "📦 Deploying storage account..."
az deployment sub create \
    --name "mustrust-storage-$(date +%Y%m%d-%H%M%S)" \
    --location japaneast \
    --template-file bicep/main.bicep \
    --parameters bicep/main.bicepparam

DEPLOYMENT_EXIT_CODE=$?

if [ $DEPLOYMENT_EXIT_CODE -ne 0 ]; then
    echo "❌ Deployment failed"
    echo ""
    echo "Common issues:"
    echo "  • Soft-deleted resources: Check for soft-deleted Cognitive Services resources"
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
