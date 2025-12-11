#!/bin/bash
set -e

# Setup Event Grid Subscription
# Run this AFTER deploying function code

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

if [ -z "$CUSTOMER" ] || [ -z "$ENVIRONMENT" ]; then
  echo -e "${RED}❌ Error: Could not read customer/environment from bicepparam${NC}"
  exit 1
fi

RESOURCE_GROUP="rg-mustrust-${CUSTOMER}-${ENVIRONMENT}"
WEB_STORAGE_ACCOUNT="stmustrustweb${CUSTOMER}${ENVIRONMENT}"
FUNCTION_APP="func-mustrust-preprocessor-${CUSTOMER}-${ENVIRONMENT}"
ANALYZER_FUNCTION_APP="func-mustrust-analyzer-${CUSTOMER}-${ENVIRONMENT}"

echo -e "Configuration:"
echo -e "  Customer:           ${GREEN}${CUSTOMER}${NC}"
echo -e "  Environment:        ${GREEN}${ENVIRONMENT}${NC}"
echo -e "  Resource Group:     ${GREEN}${RESOURCE_GROUP}${NC}"
echo -e "  Web Storage:        ${GREEN}${WEB_STORAGE_ACCOUNT}${NC}"
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

ACCOUNT_EMAIL=$(az account show --query user.name -o tsv 2>/dev/null || echo "Unknown")
echo -e "${GREEN}✅ Logged in as: ${ACCOUNT_EMAIL}${NC}"

# Check if function app exists
echo -e "${BLUE}🔍 Checking if function app exists...${NC}"
if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
  echo -e "${RED}❌ Error: Function app ${FUNCTION_APP} not found${NC}"
  echo "Please run ./setup-environment.sh first"
  exit 1
fi
echo -e "${GREEN}✅ Function app exists${NC}"

# Check if EventGridTrigger function exists
echo -e "${BLUE}🔍 Checking if EventGridTrigger function is deployed...${NC}"
FUNCTION_LIST=$(az functionapp function list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")

if [[ ! "$FUNCTION_LIST" =~ "EventGridTrigger" ]]; then
  echo -e "${YELLOW}⚠️  Warning: EventGridTrigger function not found${NC}"
  echo -e "${YELLOW}Please deploy the function code first via GitHub Actions or manually${NC}"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  echo -e "${GREEN}✅ EventGridTrigger function found${NC}"
fi

# Configure CORS for frontend
echo ""
echo -e "${BLUE}🌐 Configuring CORS for frontend...${NC}"
FRONTEND_URL="https://${WEB_STORAGE_ACCOUNT}.z11.web.core.windows.net"

# Configure CORS for preprocessor
echo -e "Configuring CORS for preprocessor..."
CURRENT_CORS=$(az functionapp cors show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "allowedOrigins" -o tsv 2>/dev/null || echo "")

if [[ "$CURRENT_CORS" =~ "$FRONTEND_URL" ]]; then
  echo -e "${GREEN}✅ Preprocessor CORS already configured${NC}"
else
  echo -e "Adding CORS origin: ${FRONTEND_URL}"
  az functionapp cors add \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --allowed-origins "$FRONTEND_URL" \
    --output none
  echo -e "${GREEN}✅ Preprocessor CORS configured${NC}"
fi

# Configure CORS for analyzer
echo -e "Configuring CORS for analyzer..."
ANALYZER_CORS=$(az functionapp cors show --name "$ANALYZER_FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "allowedOrigins" -o tsv 2>/dev/null || echo "")

if [[ "$ANALYZER_CORS" =~ "$FRONTEND_URL" ]]; then
  echo -e "${GREEN}✅ Analyzer CORS already configured${NC}"
else
  echo -e "Adding CORS origin: ${FRONTEND_URL}"
  az functionapp cors add \
    --name "$ANALYZER_FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --allowed-origins "$FRONTEND_URL" \
    --output none
  echo -e "${GREEN}✅ Analyzer CORS configured${NC}"
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
    containerName="web-input-files" \
  --output table

if [ $? -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✅ Event Grid Subscription Created!${NC}"
  echo "======================================"
  echo ""
  echo "Files uploaded to 'bronze-input-files' will now trigger the EventGridTrigger function."
  echo ""
  echo -e "${BLUE}To test:${NC}"
  echo "  az storage blob upload \\"
  echo "    --account-name $WEB_STORAGE_ACCOUNT \\"
  echo "    --container-name web-input-files \\"
  echo "    --name test.pdf \\"
  echo "    --file /path/to/your/test.pdf"
  echo ""
  echo "Or use the frontend: https://${WEB_STORAGE_ACCOUNT}.z11.web.core.windows.net/"
else
  echo -e "${RED}❌ Event Grid deployment failed${NC}"
  exit 1
fi
