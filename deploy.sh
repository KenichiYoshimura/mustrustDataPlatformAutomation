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
DEPLOYMENT_OUTPUT=$(az deployment sub create \
    --name "mustrust-storage-$(date +%Y%m%d-%H%M%S)" \
    --location japaneast \
    --template-file bicep/main.bicep \
    --parameters bicep/main.bicepparam \
    --output json 2>&1)

DEPLOYMENT_EXIT_CODE=$?
echo "$DEPLOYMENT_OUTPUT" > deployment-output.json

if [ $DEPLOYMENT_EXIT_CODE -ne 0 ]; then
    echo "❌ Deployment failed"
    echo "$DEPLOYMENT_OUTPUT"
    exit 1
fi

# Show results
echo ""
echo "✅ Deployment Complete!"
echo "======================="
echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs | to_entries[] | "\(.key): \(.value.value)"'
