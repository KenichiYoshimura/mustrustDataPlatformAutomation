#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Setup Event Grid Subscription
# Run this AFTER deploying function code
#
# Environment variables:
#   FORCE=1     - Skip EventGridTrigger check and continue
#   VERBOSE=1   - Enable debug output (set -x)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration flags
FORCE="${FORCE:-0}"
VERBOSE="${VERBOSE:-0}"
CONTAINER_NAME="web-input-files"

[[ "$VERBOSE" -eq 1 ]] && set -x

echo -e "${BLUE}🔔 Event Grid Subscription Setup${NC}"
echo "========================================"
echo ""

# Check if bicepparam exists
if [ ! -f "bicep/main.bicepparam" ]; then
  echo -e "${RED}❌ Error: bicep/main.bicepparam not found${NC}"
  exit 1
fi

# Extract customer and environment from bicepparam
CUSTOMER=$(grep "param customerName" bicep/main.bicepparam | sed "s/.*= '\(.*\)'/\1/")
ENVIRONMENT=$(grep "param environment" bicep/main.bicepparam | sed "s/.*= '\(.*\)'/\1/")

# Validate parameters
if [ -z "$CUSTOMER" ] || [ -z "$ENVIRONMENT" ]; then
  echo -e "${RED}❌ Error: Could not read customer/environment from bicepparam${NC}"
  exit 1
fi

# Validate naming rules
if [[ ! "$CUSTOMER" =~ ^[a-z0-9]+$ ]]; then
  echo -e "${RED}❌ Error: Customer name must be lowercase alphanumeric only${NC}"
  exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Environment must be dev, test, or prod${NC}"
  exit 1
fi

RESOURCE_GROUP="rg-mustrust-${CUSTOMER}-${ENVIRONMENT}"
WEB_STORAGE_ACCOUNT="stmustrustweb${CUSTOMER}${ENVIRONMENT}"
FUNCTION_APP="func-mustrust-preprocessor-${CUSTOMER}-${ENVIRONMENT}"
ANALYZER_FUNCTION_APP="func-mustrust-analyzer-${CUSTOMER}-${ENVIRONMENT}"

# Validate storage account name length (max 24 chars)
if [ ${#WEB_STORAGE_ACCOUNT} -gt 24 ]; then
  echo -e "${RED}❌ Error: Storage account name too long (${#WEB_STORAGE_ACCOUNT} > 24): ${WEB_STORAGE_ACCOUNT}${NC}"
  exit 1
fi

echo -e "Configuration:"
echo -e "  Customer:           ${GREEN}${CUSTOMER}${NC}"
echo -e "  Environment:        ${GREEN}${ENVIRONMENT}${NC}"
echo -e "  Resource Group:     ${GREEN}${RESOURCE_GROUP}${NC}"
echo -e "  Web Storage:        ${GREEN}${WEB_STORAGE_ACCOUNT}${NC}"
echo -e "  Container:          ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "  Preprocessor App:   ${GREEN}${FUNCTION_APP}${NC}"
echo -e "  Analyzer App:       ${GREEN}${ANALYZER_FUNCTION_APP}${NC}"
echo ""

# Check Azure login
echo -e "${BLUE}🔐 Checking Azure CLI login...${NC}"
if ! az account show &> /dev/null; then
  echo -e "${RED}❌ Not logged in to Azure CLI${NC}"
  echo "Please run: az login"
  exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ACCOUNT_EMAIL=$(az account show --query user.name -o tsv 2>/dev/null || echo "Service Principal")
echo -e "${GREEN}✅ Logged in as: ${ACCOUNT_EMAIL}${NC}"
echo -e "   Subscription: ${SUBSCRIPTION_ID}"

# Check resource group exists
echo -e "${BLUE}🔍 Checking resource group...${NC}"
if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo -e "${RED}❌ Error: Resource group ${RESOURCE_GROUP} not found${NC}"
  echo "Please run ./setup-environment.sh first"
  exit 1
fi
echo -e "${GREEN}✅ Resource group exists${NC}"

# Check storage account exists
echo -e "${BLUE}🔍 Checking storage account...${NC}"
if ! az storage account show --name "$WEB_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo -e "${RED}❌ Error: Storage account ${WEB_STORAGE_ACCOUNT} not found${NC}"
  echo "Please run ./setup-environment.sh first"
  exit 1
fi
echo -e "${GREEN}✅ Storage account exists${NC}"

# Check preprocessor function app exists
echo -e "${BLUE}🔍 Checking preprocessor function app...${NC}"
if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo -e "${RED}❌ Error: Function app ${FUNCTION_APP} not found${NC}"
  echo "Please run ./setup-environment.sh first"
  exit 1
fi
echo -e "${GREEN}✅ Preprocessor function app exists${NC}"

# Check analyzer function app exists
echo -e "${BLUE}🔍 Checking analyzer function app...${NC}"
if ! az functionapp show --name "$ANALYZER_FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo -e "${YELLOW}⚠️  Warning: Analyzer function app ${ANALYZER_FUNCTION_APP} not found${NC}"
  echo -e "${YELLOW}CORS configuration for analyzer will be skipped${NC}"
  ANALYZER_EXISTS=0
else
  echo -e "${GREEN}✅ Analyzer function app exists${NC}"
  ANALYZER_EXISTS=1
fi

# Check if EventGridTrigger function exists
echo -e "${BLUE}🔍 Checking if EventGridTrigger function is deployed...${NC}"
FUNCTION_LIST=$(az functionapp function list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")

if [[ ! "$FUNCTION_LIST" =~ "EventGridTrigger" ]]; then
  echo -e "${YELLOW}⚠️  Warning: EventGridTrigger function not found in ${FUNCTION_APP}${NC}"
  echo -e "${YELLOW}Please deploy the function code first via GitHub Actions or manually${NC}"
  if [[ "$FORCE" -eq 1 ]]; then
    echo -e "${YELLOW}FORCE=1 set, continuing anyway...${NC}"
  else
    echo -e "${RED}Run with FORCE=1 to proceed anyway${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}✅ EventGridTrigger function found${NC}"
fi

# Configure CORS for new secure architecture
# Architecture: Browser → Preprocessor → Analyzer
# - Preprocessor: Allows frontend origin (browser calls it)
# - Analyzer: Only Azure Portal (backend-to-backend communication only)
# Note: CORS does not affect Event Grid delivery (server-to-server)
echo ""
echo -e "${BLUE}🌐 Configuring CORS for secure architecture...${NC}"

# Dynamically resolve frontend URL from static website endpoint
FRONTEND_URL=$(az storage account show \
  --name "$WEB_STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "primaryEndpoints.web" -o tsv 2>/dev/null | sed 's:/$::')

if [[ -z "$FRONTEND_URL" ]]; then
  echo -e "${RED}❌ Error: Static website endpoint not enabled for ${WEB_STORAGE_ACCOUNT}${NC}"
  echo "Enable static website first with:"
  echo "  az storage blob service-properties update --account-name \"$WEB_STORAGE_ACCOUNT\" --static-website --index-document index.html"
  exit 1
fi

echo -e "Frontend URL: ${GREEN}${FRONTEND_URL}${NC}"

# Configure CORS for preprocessor (allow frontend)
echo -e "Configuring CORS for preprocessor (allows frontend)..."
CURRENT_CORS=$(az functionapp cors show \
  --name "$FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --query "allowedOrigins" -o tsv 2>/dev/null || echo "")

if [[ "$CURRENT_CORS" =~ "$FRONTEND_URL" ]]; then
  echo -e "${GREEN}✅ Preprocessor CORS already configured for frontend${NC}"
else
  echo -e "Adding CORS origin: ${FRONTEND_URL}"
  az functionapp cors add \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --allowed-origins "$FRONTEND_URL" \
    --output none --only-show-errors
  echo -e "${GREEN}✅ Preprocessor CORS configured${NC}"
fi

# Configure CORS for analyzer (remove frontend, keep only Azure Portal)
if [[ "$ANALYZER_EXISTS" -eq 1 ]]; then
  echo -e "Configuring CORS for analyzer (backend-only)..."
  echo -e "${YELLOW}🔒 Removing frontend origin from analyzer (security hardening)${NC}"

  # Get current CORS settings
  ANALYZER_CORS_LIST=$(az functionapp cors show \
    --name "$ANALYZER_FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "allowedOrigins[]" -o tsv 2>/dev/null || echo "")

  # Remove frontend origin if it exists
  if [[ "$ANALYZER_CORS_LIST" =~ "$FRONTEND_URL" ]]; then
    echo -e "Removing frontend origin from analyzer..."
    az functionapp cors remove \
      --name "$ANALYZER_FUNCTION_APP" \
      --resource-group "$RESOURCE_GROUP" \
      --allowed-origins "$FRONTEND_URL" \
      --output none --only-show-errors
    echo -e "${GREEN}✅ Frontend origin removed from analyzer${NC}"
  else
    echo -e "${GREEN}✅ Analyzer CORS already secure (no frontend origin)${NC}"
  fi

  # Ensure Azure Portal is allowed for management
  if [[ ! "$ANALYZER_CORS_LIST" =~ "https://portal.azure.com" ]]; then
    echo -e "Adding Azure Portal origin for management..."
    az functionapp cors add \
      --name "$ANALYZER_FUNCTION_APP" \
      --resource-group "$RESOURCE_GROUP" \
      --allowed-origins "https://portal.azure.com" \
      --output none --only-show-errors
    echo -e "${GREEN}✅ Azure Portal origin added${NC}"
  fi

  echo -e "${GREEN}✅ CORS configuration complete${NC}"
  echo -e "   - Preprocessor: Frontend can access (${FRONTEND_URL})"
  echo -e "   - Analyzer: Backend-only (Azure Portal for management)"
else
  echo -e "${YELLOW}⚠️  Skipping analyzer CORS (not deployed)${NC}"
fi

# Deploy Event Grid subscription
echo ""
echo -e "${BLUE}📦 Deploying Event Grid subscription...${NC}"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/modules/eventgrid.bicep \
  --parameters \
    storageAccountName="$WEB_STORAGE_ACCOUNT" \
    functionAppName="$FUNCTION_APP" \
    containerName="$CONTAINER_NAME" \
  --output table --only-show-errors

if [ $? -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✅ Event Grid Subscription Created!${NC}"
  echo "======================================"
  echo ""
  
  # Verify subscription was created
  echo -e "${BLUE}🔍 Verifying Event Grid subscription...${NC}"
  SUBSCRIPTION_NAME="eg-web-input-files-to-preprocessor"
  if az eventgrid event-subscription show \
    --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$WEB_STORAGE_ACCOUNT" \
    --name "$SUBSCRIPTION_NAME" \
    --output none 2>/dev/null; then
    echo -e "${GREEN}✅ Event Grid subscription verified${NC}"
  else
    echo -e "${YELLOW}⚠️  Could not verify subscription (may still work)${NC}"
  fi
  
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✅ Setup Complete${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${BLUE}Configuration Summary:${NC}"
  echo -e "  Resource Group:     ${RESOURCE_GROUP}"
  echo -e "  Storage Account:    ${WEB_STORAGE_ACCOUNT}"
  echo -e "  Container:          ${CONTAINER_NAME}"
  echo -e "  Preprocessor:       ${FUNCTION_APP}"
  echo -e "  Analyzer:           ${ANALYZER_FUNCTION_APP}"
  echo -e "  Frontend URL:       ${FRONTEND_URL}"
  echo ""
  echo -e "${BLUE}Architecture:${NC}"
  echo -e "  Files uploaded to '${CONTAINER_NAME}' → EventGridTrigger → Preprocessor"
  echo -e "  Browser → Preprocessor (public) → Analyzer (backend-only)"
  echo ""
  echo -e "${BLUE}Test Upload:${NC}"
  echo "  az storage blob upload \\"
  echo "    --account-name \"$WEB_STORAGE_ACCOUNT\" \\"
  echo "    --container-name \"$CONTAINER_NAME\" \\"
  echo "    --name test.pdf \\"
  echo "    --file /path/to/your/test.pdf \\"
  echo "    --auth-mode login"
  echo ""
  echo -e "${BLUE}Frontend:${NC}"
  echo "  ${FRONTEND_URL}"
  echo ""
  echo -e "${BLUE}Monitor Logs:${NC}"
  echo "  az functionapp log tail --name \"$FUNCTION_APP\" --resource-group \"$RESOURCE_GROUP\""
  echo ""
else
  echo -e "${RED}❌ Event Grid deployment failed${NC}"
  exit 1
fi
