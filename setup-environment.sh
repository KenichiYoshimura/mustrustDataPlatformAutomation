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
    --help)
      echo "Usage: $0 --customer <name> --environment <env> --github-repo <owner/repo>"
      echo ""
      echo "Options:"
      echo "  --customer        Customer name (e.g., yys, hcs)"
      echo "  --environment     Environment (dev, test, or prod)"
      echo "  --github-repo     GitHub repository (e.g., your-org/function-app-repo)"
      echo "  --subscription    Azure subscription ID (optional)"
      echo ""
      echo "Example:"
      echo "  $0 --customer yys --environment prod --github-repo myorg/mustrust-functions"
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
STORAGE_ACCOUNT="stmustrust${CUSTOMER_NAME}${ENVIRONMENT}"
SP_NAME="github-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"

echo -e "${YELLOW}📝 Resources to be created:${NC}"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Function App:    $FUNCTION_APP"
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
echo "  • Function App: $FUNCTION_APP"
echo ""
echo -e "${GREEN}✅ GitHub Actions Credentials:${NC}"
echo "  Saved to: $CREDS_FILE"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo ""
echo "1. Add GitHub Secret:"
echo "   a. Go to: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
echo "   b. Click 'New repository secret'"
echo "   c. Name: AZURE_CREDENTIALS"
echo "   d. Value: Copy from file below"
echo ""
echo -e "${BLUE}   Credentials file content:${NC}"
echo "   ----------------------------------------"
cat "$CREDS_FILE"
echo "   ----------------------------------------"
echo ""
echo "2. Copy workflow file to your Python app repo:"
echo "   cp .github/workflows/deploy-function.yml <your-python-app-repo>/.github/workflows/"
echo ""
echo "3. Update workflow settings in deploy-function.yml:"
echo "   - CUSTOMER_NAME: '${CUSTOMER_NAME}'"
echo "   - AZURE_FUNCTIONAPP_PACKAGE_PATH: (adjust if needed)"
echo ""
echo "4. Push to GitHub:"
echo "   - Push to 'main' branch → deploys to prod"
echo "   - Push to 'develop' branch → deploys to dev"
echo ""
echo -e "${YELLOW}⚠️  Security Note:${NC}"
echo "  The credentials file ($CREDS_FILE) contains sensitive information."
echo "  After copying to GitHub Secrets, delete it:"
echo "  rm $CREDS_FILE"
echo ""
echo -e "${GREEN}🎉 Environment setup complete!${NC}"
