#!/bin/bash

# Configure shared AI service credentials for Analyzer Function App
# This script sets up Document Intelligence and Custom Vision credentials from shared resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SHARED_RG="hcsGroup"
DOC_INTELLIGENCE_NAME="surveyformextractor2"
CUSTOM_VISION_RG="CustomSymbolRecognizerGroup"
CUSTOM_VISION_NAME="customSymbolRecognizer-Prediction"
CUSTOM_VISION_ITERATION="Iteration6"

# Parse arguments
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
    --help)
      echo "Usage: $0 --customer <name> --environment <env>"
      echo ""
      echo "Options:"
      echo "  --customer        Customer name (e.g., yys, hcs)"
      echo "  --environment     Environment (dev, test, or prod)"
      echo ""
      echo "Example:"
      echo "  $0 --customer yys --environment dev"
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
if [[ -z "$CUSTOMER_NAME" ]] || [[ -z "$ENVIRONMENT" ]]; then
  echo -e "${RED}❌ Error: Missing required parameters${NC}"
  echo "Use --help for usage information"
  exit 1
fi

# Compute resource names
RESOURCE_GROUP="rg-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
ANALYZER_FUNCTION_APP="func-mustrust-analyzer-${CUSTOMER_NAME}-${ENVIRONMENT}"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Configure Analyzer AI Services              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Customer:           $CUSTOMER_NAME"
echo "  Environment:        $ENVIRONMENT"
echo "  Function App:       $ANALYZER_FUNCTION_APP"
echo "  Shared Resource RG: $SHARED_RG"
echo ""

# Get Document Intelligence credentials
echo -e "${BLUE}📥 Retrieving Document Intelligence credentials...${NC}"
DOC_INTEL_ENDPOINT=$(az cognitiveservices account show \
  --name "$DOC_INTELLIGENCE_NAME" \
  --resource-group "$SHARED_RG" \
  --query "properties.endpoint" -o tsv)

DOC_INTEL_KEY=$(az cognitiveservices account keys list \
  --name "$DOC_INTELLIGENCE_NAME" \
  --resource-group "$SHARED_RG" \
  --query "key1" -o tsv)

if [[ -z "$DOC_INTEL_ENDPOINT" ]] || [[ -z "$DOC_INTEL_KEY" ]]; then
  echo -e "${RED}❌ Failed to retrieve Document Intelligence credentials${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Document Intelligence credentials retrieved${NC}"

# Get Custom Vision credentials
echo -e "${BLUE}📥 Retrieving Custom Vision credentials...${NC}"
CV_ENDPOINT=$(az cognitiveservices account show \
  --name "$CUSTOM_VISION_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "properties.endpoint" -o tsv)

CV_KEY=$(az cognitiveservices account keys list \
  --name "$CUSTOM_VISION_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "key1" -o tsv)

if [[ -z "$CV_ENDPOINT" ]] || [[ -z "$CV_KEY" ]]; then
  echo -e "${RED}❌ Failed to retrieve Custom Vision credentials${NC}"
  exit 1
fi

# Get Custom Vision Project ID (you'll need to provide this)
echo -e "${YELLOW}⚠️  Custom Vision Project ID needs to be retrieved from Azure Portal${NC}"
echo "   Go to: https://www.customvision.ai/"
echo "   Select your circle detection project"
echo "   Settings → Project Id"
echo ""
read -p "Enter Custom Vision Project ID: " CV_PROJECT_ID

if [[ -z "$CV_PROJECT_ID" ]]; then
  echo -e "${RED}❌ Project ID is required${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Custom Vision credentials retrieved${NC}"

# Configure Function App settings
echo ""
echo -e "${BLUE}⚙️  Configuring Function App settings...${NC}"

az functionapp config appsettings set \
  --name "$ANALYZER_FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "DOCUMENT_INTELLIGENCE_ENDPOINT=$DOC_INTEL_ENDPOINT" \
    "DOCUMENT_INTELLIGENCE_KEY=$DOC_INTEL_KEY" \
    "CUSTOM_VISION_PREDICTION_ENDPOINT=$CV_ENDPOINT" \
    "CUSTOM_VISION_PREDICTION_KEY=$CV_KEY" \
    "CUSTOM_VISION_PROJECT_ID=$CV_PROJECT_ID" \
    "CUSTOM_VISION_ITERATION_NAME=$CUSTOM_VISION_ITERATION" \
  --output none

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to configure Function App settings${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Function App settings configured successfully${NC}"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Configuration Complete!                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Configured Settings:${NC}"
echo "  • DOCUMENT_INTELLIGENCE_ENDPOINT: $DOC_INTEL_ENDPOINT"
echo "  • DOCUMENT_INTELLIGENCE_KEY: ****${DOC_INTEL_KEY: -4}"
echo "  • CUSTOM_VISION_PREDICTION_ENDPOINT: $CV_ENDPOINT"
echo "  • CUSTOM_VISION_PREDICTION_KEY: ****${CV_KEY: -4}"
echo "  • CUSTOM_VISION_PROJECT_ID: $CV_PROJECT_ID"
echo "  • CUSTOM_VISION_ITERATION_NAME: $CUSTOM_VISION_ITERATION"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "  1. Deploy the Analyzer application code via GitHub Actions"
echo "  2. Test the Silver/Gold pipeline with a document upload"
echo ""
echo -e "${GREEN}🎉 Analyzer AI configuration complete!${NC}"
