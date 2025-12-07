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
FUNCTION_APP="func-mustrust-preprocessor-${CUSTOMER_NAME}-${ENVIRONMENT}"
ANALYZER_FUNCTION_APP="func-mustrust-analyzer-${CUSTOMER_NAME}-${ENVIRONMENT}"
STORAGE_ACCOUNT="stmustrust${CUSTOMER_NAME}${ENVIRONMENT}"
SP_NAME="github-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"

echo -e "${YELLOW}📝 Resources to be created:${NC}"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Function App:    $FUNCTION_APP"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "  Analyzer App:    $ANALYZER_FUNCTION_APP"
fi
echo "  Service Principal: $SP_NAME"
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

# Create service principal for GitHub Actions
echo -e "${BLUE}🔑 Creating service principal for GitHub Actions...${NC}"

# Check if service principal already exists
SP_EXISTS=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [[ -n "$SP_EXISTS" ]]; then
  echo -e "${YELLOW}⚠️  Service principal '$SP_NAME' already exists${NC}"
  echo "Resetting credentials..."
  SP_JSON=$(az ad sp credential reset --id "$SP_EXISTS" --sdk-auth 2>/dev/null)
else
  echo "Creating new service principal..."
  SP_JSON=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    --sdk-auth 2>/dev/null)
fi

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to create service principal${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Service principal created${NC}"
echo ""

# Save credentials to a temporary file
CREDS_FILE=".azure-credentials-${CUSTOMER_NAME}-${ENVIRONMENT}.json"
echo "$SP_JSON" > "$CREDS_FILE"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Setup Complete!                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Infrastructure Resources Created:${NC}"
echo "  • Resource Group: $RESOURCE_GROUP"
echo "  • Storage Account: $STORAGE_ACCOUNT"
echo "    - Containers: bronze-input-files, bronze-processed-files, bronze-invalid-files"
echo "    - Queue: bronze-file-processing-queue"
echo "  • Function App (Preprocessor): $FUNCTION_APP"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
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
echo "   • Preprocessor: Push to main/develop or use GitHub Actions"
if [[ "$DEPLOY_ANALYZER" == "true" ]]; then
  echo "   • Analyzer: Push to main/develop or use GitHub Actions"
fi
echo ""
echo -e "${YELLOW}⚠️  Security Note:${NC}"
echo "  The credentials file contains sensitive information."
echo "  After copying to GitHub Secrets, delete it:"
echo "  rm $CREDS_FILE"
echo ""
echo -e "${GREEN}🎉 Environment setup complete!${NC}"
