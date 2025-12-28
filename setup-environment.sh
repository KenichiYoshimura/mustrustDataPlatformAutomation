#!/bin/bash
set -e

# MusTrusT Environment Setup Script
# This script sets up a complete environment: infrastructure + GitHub deployment credentials

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-6a6d110d-80ef-424a-b8bb-24439063ffb2}"
CUSTOMER_NAME=""
ENVIRONMENT=""
GITHUB_REPO="KenichiYoshimura/mustrustDataPlatformProcessor"
DEPLOY_ANALYZER=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --customer)
      CUSTOMER_NAME="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --subscription)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --with-analyzer)
      DEPLOY_ANALYZER=true
      shift
      ;;
    --help)
      echo "Usage: $0 --customer <name> --environment <env> [--with-analyzer] --github-repo <owner/repo>"
      echo ""
      echo "Options:"
      echo "  --customer        Customer name (e.g., yys, hcs)"
      echo "  --environment     Environment (dev, test, or prod)"
      echo "  --with-analyzer   Deploy Cosmos DB + Analyzer Function App (Silver/Gold layers)"
      echo "  --github-repo     GitHub repository (e.g., your-org/function-app-repo)"
      echo "  --subscription    Azure subscription ID (optional)"
      echo ""
      echo "Example:"
      echo "  $0 --customer yys --environment dev --with-analyzer"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$CUSTOMER_NAME" ]] || [[ -z "$ENVIRONMENT" ]] || [[ -z "$GITHUB_REPO" ]]; then
  echo -e "${RED}❌ Error: Missing required parameters${NC}"
  echo "Use --help for usage information"
  exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Environment must be dev, test, or prod${NC}"
  exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MusTrusT Environment Setup                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Customer:      $CUSTOMER_NAME"
echo "  Environment:   $ENVIRONMENT"
echo "  Subscription:  $SUBSCRIPTION_ID"
echo "  GitHub Repo:   $GITHUB_REPO"
echo ""

# Compute resource names
RESOURCE_GROUP="rg-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
APP_SERVICE_PREPROCESSOR="app-mustrust-preprocessor-${CUSTOMER_NAME}-${ENVIRONMENT}"
ANALYZER_FUNCTION_APP="func-mustrust-analyzer-${CUSTOMER_NAME}-${ENVIRONMENT}"
WEB_STORAGE_ACCOUNT="stmustrustweb${CUSTOMER_NAME}${ENVIRONMENT}"
PREPROCESSOR_STORAGE_ACCOUNT="stpreproc${CUSTOMER_NAME}${ENVIRONMENT}"
ANALYZER_STORAGE_ACCOUNT="stmustrust${CUSTOMER_NAME}${ENVIRONMENT}"
SP_NAME="github-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"

echo -e "${YELLOW}📝 Resources to be created:${NC}"
echo "  Resource Group:     $RESOURCE_GROUP"
echo "  Web Storage:        $WEB_STORAGE_ACCOUNT (frontend + uploads)"
echo "  Preprocessor Storage: $PREPROCESSOR_STORAGE_ACCOUNT (staging uploads)"
echo "  Analyzer Storage:   $ANALYZER_STORAGE_ACCOUNT (processing + data)"
echo "  Preprocessor (App Service S1): $APP_SERVICE_PREPROCESSOR (with Easy Auth)"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "  Analyzer App:       $ANALYZER_FUNCTION_APP"
fi
echo "  Service Principal:  $SP_NAME"
echo ""

# Check if user is logged in
echo -e "${BLUE}🔐 Checking Azure CLI login...${NC}"
if ! az account show &> /dev/null; then
  echo -e "${RED}❌ Not logged in to Azure CLI${NC}"
  echo "Please run: az login"
  exit 1
fi

CURRENT_USER=$(az account show --query user.name -o tsv)
echo -e "${GREEN}✅ Logged in as: $CURRENT_USER${NC}"

# Set subscription
echo -e "${BLUE}📌 Setting subscription...${NC}"
az account set --subscription "$SUBSCRIPTION_ID"
echo -e "${GREEN}✅ Subscription set${NC}"
echo ""

# Update bicep parameters
echo -e "${BLUE}📝 Updating Bicep parameters...${NC}"
cat > bicep/main.bicepparam << EOF
using './main.bicep'

// NOTE: Subscription is set via Azure CLI before deployment
// Run: az account set --subscription "your-subscription-id"
// Or use AZURE_SUBSCRIPTION_ID environment variable in deploy.sh

// Basic Configuration
param customerName = '${CUSTOMER_NAME}'
param environment = '${ENVIRONMENT}'
param location = 'japaneast'   // Azure region

// Storage Account Settings
param storageAccountSku = 'Standard_LRS' // Standard_LRS is cheapest

// Silver & Gold Layer Deployment
// Set to true to deploy Cosmos DB and Silver/Gold Function Apps
param deploySilverGold = ${DEPLOY_ANALYZER}

// App Service Preprocessor Deployment (Windows S1 with Easy Auth)
param deployAppServicePreprocessor = true

// Azure AD Configuration for Easy Auth
param aadTenantId = ''
param aadClientId = ''
param aadClientSecret = ''
EOF
echo -e "${GREEN}✅ Parameters updated${NC}"

# Deploy infrastructure
echo ""
echo -e "${BLUE}🚀 Deploying infrastructure...${NC}"
./deploy.sh --subscription "$SUBSCRIPTION_ID"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Infrastructure deployment failed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Infrastructure deployed successfully${NC}"
echo ""

# Create or reuse universal service principal for GitHub Actions (subscription-level, works for ALL customers/environments)
echo -e "${BLUE}🔑 Setting up service principal for GitHub Actions...${NC}"

# Use single universal SP so one credential works for all customers and environments
UNIVERSAL_SP_NAME="github-mustrust-automation"
echo -e "Service Principal: ${BLUE}${UNIVERSAL_SP_NAME}${NC} (subscription-scoped, works for ALL customers/environments)"

# Check if universal SP already exists
SP_EXISTS=$(az ad sp list --display-name "$UNIVERSAL_SP_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [[ -n "$SP_EXISTS" ]]; then
  echo -e "${YELLOW}✅ Service principal '$UNIVERSAL_SP_NAME' already exists (reusing)${NC}"
  echo "Refreshing credentials..."
  SP_JSON=$(az ad sp credential reset --id "$SP_EXISTS" --sdk-auth 2>/dev/null)
else
  echo "Creating new service principal..."
  SP_JSON=$(az ad sp create-for-rbac \
    --name "$UNIVERSAL_SP_NAME" \
    --role contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --sdk-auth 2>/dev/null)
fi

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to create service principal${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Service principal created${NC}"
echo ""

# Save credentials to a temporary file
CREDS_FILE=".azure-credentials.json"
echo "$SP_JSON" > "$CREDS_FILE"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Setup Complete!                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Infrastructure Resources Created:${NC}"
echo "  • Resource Group: $RESOURCE_GROUP"
echo ""
echo "  • Web Storage: $WEB_STORAGE_ACCOUNT"
echo "    - Container: web-input-files (file uploads)"
echo "    - Static Website: Enabled ($web container)"
echo ""
echo "  • Preprocessor Storage: $PREPROCESSOR_STORAGE_ACCOUNT"
echo "    - Container: preprocessor-uploads (staging area)"
echo "    - Container: preprocessor-processing (background jobs)"
echo "    - Queue: preprocessor-file-processing-queue"
echo ""
echo "  • Analyzer Storage: $ANALYZER_STORAGE_ACCOUNT"
echo "    - Containers: bronze-processed-files, bronze-invalid-files"
echo "    - Queue: bronze-file-processing-queue"
echo ""
echo "  • App Service (Preprocessor): $APP_SERVICE_PREPROCESSOR"
echo "    - Type: Linux S1 with Easy Auth support"
echo "    - Staging: $PREPROCESSOR_STORAGE_ACCOUNT/preprocessor-uploads"
echo "    - Forwards to: $ANALYZER_STORAGE_ACCOUNT/bronze-processed-files"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo ""
  echo "  • Function App (Analyzer): $ANALYZER_FUNCTION_APP"
  echo "  • Cosmos DB: cosmos-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
  echo "  • Language Service: lang-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
fi
echo ""
echo -e "${GREEN}✅ GitHub Actions Credentials:${NC}"
echo "  Service Principal saved to: $CREDS_FILE"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo ""
echo "══════════════════════════════════════════════════════"
echo "1️⃣  Add GitHub Secret: AZURE_CREDENTIALS"
echo "══════════════════════════════════════════════════════"
echo "   This ONE secret works for BOTH Preprocessor and Analyzer apps!"
echo ""
echo "   Preprocessor Repository:"
echo "   https://github.com/KenichiYoshimura/mustrustDataPlatformProcessor/settings/secrets/actions"
echo ""
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "   Analyzer Repository:"
  echo "   https://github.com/KenichiYoshimura/mustrustDataPlatformAnalyzer/settings/secrets/actions"
  echo ""
fi
echo "   Secret Details:"
echo "   - Name:  AZURE_CREDENTIALS"
echo "   - Value: Copy from $CREDS_FILE (shown below)"
echo ""
echo -e "${BLUE}   Credentials content:${NC}"
echo "   ----------------------------------------"
cat "$CREDS_FILE"
echo "   ----------------------------------------"
echo ""

if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "══════════════════════════════════════════════════════"
  echo "2️⃣  Configure Shared AI Credentials (MANUAL)"
  echo "══════════════════════════════════════════════════════"
  echo "   The Analyzer app needs shared AI service credentials:"
  echo ""
  echo "   Run this command:"
  echo "   ./configure-analyzer-ai.sh --customer $CUSTOMER_NAME --environment $ENVIRONMENT"
  echo ""
  echo "   Or manually configure:"
  echo "   az functionapp config appsettings set \\"
  echo "     --name $ANALYZER_FUNCTION_APP \\"
  echo "     --resource-group $RESOURCE_GROUP \\"
  echo "     --settings \\"
  echo "       \"DOCUMENT_INTELLIGENCE_ENDPOINT=<surveyformextractor2-endpoint>\" \\"
  echo "       \"DOCUMENT_INTELLIGENCE_KEY=<surveyformextractor2-key>\" \\"
  echo "       \"CUSTOM_VISION_PREDICTION_ENDPOINT=<circleMarkerRecognizer-endpoint>\" \\"
  echo "       \"CUSTOM_VISION_PREDICTION_KEY=<circleMarkerRecognizer-key>\" \\"
  echo "       \"CUSTOM_VISION_PROJECT_ID=<circleMarkerRecognizer-project-id>\" \\"
  echo "       \"CUSTOM_VISION_ITERATION_NAME=Iteration6\""
  echo ""
  echo "   Get credentials from Azure Portal → hcsGroup resource group"
  echo ""
fi

echo "══════════════════════════════════════════════════════"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "3️⃣  Deploy Application Code"
else
  echo "2️⃣  Deploy Application Code"
fi
echo "══════════════════════════════════════════════════════"
echo "   Preprocessor (App Service):"
echo "   cd mustrustDataPlatformProcessor"
echo "   az webapp up --resource-group $RESOURCE_GROUP --name $APP_SERVICE_PREPROCESSOR --runtime PYTHON:3.11"
echo ""
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "   Analyzer:"
  echo "   cd mustrustDataPlatformAnalyzer"
  echo "   func azure functionapp publish $ANALYZER_FUNCTION_APP"
  echo ""
fi
echo "   Frontend (Static Website):"
echo "   cd mustrustDataPlatformProcessor"
echo "   ./deploy-frontend.sh $WEB_STORAGE_ACCOUNT"
echo ""
echo "   Frontend URL: https://${WEB_STORAGE_ACCOUNT}.z11.web.core.windows.net/"
echo ""
echo "══════════════════════════════════════════════════════"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "4️⃣  Setup EventGrid (after code deployment)"
else
  echo "3️⃣  Setup EventGrid (after code deployment)"
fi
echo "══════════════════════════════════════════════════════"
echo "   Note: Event Grid is only needed if Analyzer is deployed"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "   cd MusTrusTDataPlatformInfra"
  echo "   ./setup-eventgrid.sh"
fi
echo ""
echo -e "${YELLOW}⚠️  Security Note:${NC}"
echo "  The credentials file contains sensitive information."
echo "  After copying to GitHub Secrets, delete it:"
echo "  rm $CREDS_FILE"
echo ""
echo -e "${GREEN}🎉 Environment setup complete!${NC}"
