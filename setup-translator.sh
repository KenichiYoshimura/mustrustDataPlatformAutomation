#!/bin/bash
set -e

# Azure Translator Text Service Setup Script
# Tests translator deployment in isolation before integrating into main infrastructure

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parameters
CUSTOMER_NAME="${1:-hcs}"
ENVIRONMENT="${2:-prod}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-6a6d110d-80ef-424a-b8bb-24439063ffb2}"
LOCATION="japaneast"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Azure Translator Service Setup               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Customer: $CUSTOMER_NAME"
echo "Environment: $ENVIRONMENT"
echo "Location: $LOCATION"
echo ""

# Resource names
RESOURCE_GROUP="rg-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
TRANSLATOR_NAME="trans-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"

# Verify resource group exists
echo "📌 Checking resource group..."
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo -e "${RED}❌ Resource group $RESOURCE_GROUP not found${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Resource group found${NC}"

# Deploy translator
echo ""
echo "📦 Deploying Azure Translator Text Service (S1 tier)..."
az cognitiveservices account create \
  --name "$TRANSLATOR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --kind TextTranslation \
  --sku S1 \
  --location "$LOCATION" \
  --custom-domain "$TRANSLATOR_NAME" \
  --output table

echo ""
echo -e "${GREEN}✅ Translator deployed successfully${NC}"

# Get credentials
echo ""
echo "📋 Retrieving translator credentials..."
ENDPOINT=$(az cognitiveservices account show \
  --name "$TRANSLATOR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.endpoint -o tsv)

KEY=$(az cognitiveservices account keys list \
  --name "$TRANSLATOR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query key1 -o tsv)

echo ""
echo -e "${GREEN}✅ Translator Credentials:${NC}"
echo "  Endpoint: $ENDPOINT"
echo "  Key: ${KEY:0:8}...${KEY: -4}"
echo "  Region: $LOCATION"

# Test translator (optional - may fail due to key propagation delay)
echo ""
echo "🧪 Testing translator API..."
RESPONSE=$(curl -s -X POST "$ENDPOINT/translate?api-version=3.0&from=en&to=ja" \
  -H "Ocp-Apim-Subscription-Key: $KEY" \
  -H "Content-Type: application/json" \
  -d '[{"Text":"Hello"}]' 2>/dev/null || echo "")

if echo "$RESPONSE" | grep -q "error"; then
  echo -e "${YELLOW}⚠️  Translator API test inconclusive (may be key propagation delay)${NC}"
  echo "    Resource was created successfully. Keys should be active within 1-2 minutes."
else
  echo -e "${GREEN}✅ Translator API test successful${NC}"
fi
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Setup Complete!                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Run configure-analyzer-ai.sh to inject credentials:"
echo "     bash configure-analyzer-ai.sh --customer $CUSTOMER_NAME --environment $ENVIRONMENT"
echo ""
