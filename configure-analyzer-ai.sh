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
CLASSIFIER_RG="hygieneMasterGroup"
CLASSIFIER_NAME="hygieneMasterClassifer"
CLASSIFIER_ID="hygiene-master-form-classifier"
CUSTOM_VISION_RG="CustomSymbolRecognizerGroup"
CUSTOM_VISION_NAME="customSymbolRecognizer-Prediction"
CUSTOM_VISION_TRAINING_NAME="customSymbolRecognizer"

# Hardcoded shared values (common across all customers and environments)
BANK_CUSTOM_MODEL_ID="hcs-survery-extraction-model2"
BANK_CUSTOM_VISION_ENDPOINT="https://japaneast.api.cognitive.microsoft.com/"
BANK_CUSTOM_VISION_PREDICTION_KEY="d3b436df50794eb5a39bfcad78b89ca1"
BANK_CUSTOM_VISION_PROJECT_ID="3b991de4-fcd4-415a-b24a-7e42c6eb53dd"
BANK_CUSTOM_VISION_ITERATION_NAME="Iteration6"
CUSTOM_VISION_PROJECT_ID="deb4d033-d8af-4ad5-88a1-0d70affefee4"
CUSTOM_VISION_ITERATION_NAME="Iteration7"
# Note: AZURE_TRANSLATOR_* values should be retrieved from deployed Language Service
# They will be fetched dynamically below from the deployed resources
AZURE_TRANSLATOR_ENDPOINT=""
AZURE_TRANSLATOR_KEY=""
AZURE_TRANSLATOR_REGION="japaneast"

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

# Get Classifier credentials (separate resource)
echo -e "${BLUE}📥 Retrieving Classifier credentials...${NC}"
CLASSIFIER_ENDPOINT=$(az cognitiveservices account show \
  --name "$CLASSIFIER_NAME" \
  --resource-group "$CLASSIFIER_RG" \
  --query "properties.endpoint" -o tsv)

CLASSIFIER_KEY=$(az cognitiveservices account keys list \
  --name "$CLASSIFIER_NAME" \
  --resource-group "$CLASSIFIER_RG" \
  --query "key1" -o tsv)

if [[ -z "$CLASSIFIER_ENDPOINT" ]] || [[ -z "$CLASSIFIER_KEY" ]]; then
  echo -e "${RED}❌ Failed to retrieve Classifier credentials${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Classifier credentials retrieved${NC}"

# Get Custom Vision Prediction credentials
echo -e "${BLUE}📥 Retrieving Custom Vision Prediction credentials...${NC}"
CV_PREDICTION_ENDPOINT=$(az cognitiveservices account show \
  --name "$CUSTOM_VISION_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "properties.endpoint" -o tsv)

CV_PREDICTION_KEY=$(az cognitiveservices account keys list \
  --name "$CUSTOM_VISION_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "key1" -o tsv)

if [[ -z "$CV_PREDICTION_ENDPOINT" ]] || [[ -z "$CV_PREDICTION_KEY" ]]; then
  echo -e "${RED}❌ Failed to retrieve Custom Vision Prediction credentials${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Custom Vision Prediction credentials retrieved${NC}"

# Get Custom Vision Training credentials (shared across all instances)
echo -e "${BLUE}📥 Retrieving Custom Vision Training credentials...${NC}"
CV_TRAINING_ENDPOINT=$(az cognitiveservices account show \
  --name "$CUSTOM_VISION_TRAINING_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "properties.endpoint" -o tsv)

CV_TRAINING_KEY=$(az cognitiveservices account keys list \
  --name "$CUSTOM_VISION_TRAINING_NAME" \
  --resource-group "$CUSTOM_VISION_RG" \
  --query "key1" -o tsv)

if [[ -z "$CV_TRAINING_ENDPOINT" ]] || [[ -z "$CV_TRAINING_KEY" ]]; then
  echo -e "${RED}❌ Failed to retrieve Custom Vision Training credentials${NC}"
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
    "CLASSIFIER_ENDPOINT=$CLASSIFIER_ENDPOINT" \
    "CLASSIFIER_ENDPOINT_AZURE_API_KEY=$CLASSIFIER_KEY" \
    "CLASSIFIER_ID=$CLASSIFIER_ID" \
    "BANK_DOCUMENT_INTELLIGENCE_ENDPOINT=$DOC_INTEL_ENDPOINT" \
    "BANK_DOCUMENT_INTELLIGENCE_KEY=$DOC_INTEL_KEY" \
    "BANK_CUSTOM_MODEL_ID=$BANK_CUSTOM_MODEL_ID" \
    "BANK_CUSTOM_VISION_ENDPOINT=$BANK_CUSTOM_VISION_ENDPOINT" \
    "BANK_CUSTOM_VISION_PREDICTION_KEY=$BANK_CUSTOM_VISION_PREDICTION_KEY" \
    "BANK_CUSTOM_VISION_PROJECT_ID=$BANK_CUSTOM_VISION_PROJECT_ID" \
    "BANK_CUSTOM_VISION_ITERATION_NAME=$BANK_CUSTOM_VISION_ITERATION_NAME" \
    "CUSTOM_VISION_PREDICTION_ENDPOINT=$CV_PREDICTION_ENDPOINT" \
    "CUSTOM_VISION_PREDICTION_KEY=$CV_PREDICTION_KEY" \
    "CUSTOM_VISION_ENDPOINT=$CV_PREDICTION_ENDPOINT" \
    "CUSTOM_VISION_KEY=$CV_PREDICTION_KEY" \
    "CUSTOM_VISION_PROJECT_ID=$CUSTOM_VISION_PROJECT_ID" \
    "CUSTOM_VISION_ITERATION_NAME=$CUSTOM_VISION_ITERATION_NAME" \
    "AZURE_TRANSLATOR_ENDPOINT=$AZURE_TRANSLATOR_ENDPOINT" \
    "AZURE_TRANSLATOR_KEY=$AZURE_TRANSLATOR_KEY" \
    "AZURE_TRANSLATOR_REGION=$AZURE_TRANSLATOR_REGION" \
    "BANK_SURVEY_FORM_DEBUG=false" \
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
echo "  • CLASSIFIER_ENDPOINT: $CLASSIFIER_ENDPOINT"
echo "  • CLASSIFIER_ENDPOINT_AZURE_API_KEY: ****${CLASSIFIER_KEY: -4}"
echo "  • CLASSIFIER_ID: $CLASSIFIER_ID"
echo "  • BANK_DOCUMENT_INTELLIGENCE_ENDPOINT: $DOC_INTEL_ENDPOINT"
echo "  • BANK_DOCUMENT_INTELLIGENCE_KEY: ****${DOC_INTEL_KEY: -4}"
echo "  • BANK_CUSTOM_MODEL_ID: $BANK_CUSTOM_MODEL_ID"
echo "  • BANK_CUSTOM_VISION_ENDPOINT: $BANK_CUSTOM_VISION_ENDPOINT"
echo "  • BANK_CUSTOM_VISION_PREDICTION_KEY: ****${BANK_CUSTOM_VISION_PREDICTION_KEY: -4}"
echo "  • BANK_CUSTOM_VISION_PROJECT_ID: $BANK_CUSTOM_VISION_PROJECT_ID"
echo "  • BANK_CUSTOM_VISION_ITERATION_NAME: $BANK_CUSTOM_VISION_ITERATION_NAME"
echo "  • CUSTOM_VISION_PREDICTION_ENDPOINT: $CV_PREDICTION_ENDPOINT"
echo "  • CUSTOM_VISION_PREDICTION_KEY: ****${CV_PREDICTION_KEY: -4}"
echo "  • CUSTOM_VISION_ENDPOINT: $CV_PREDICTION_ENDPOINT"
echo "  • CUSTOM_VISION_KEY: ****${CV_PREDICTION_KEY: -4}"
echo "  • CUSTOM_VISION_PROJECT_ID: $CUSTOM_VISION_PROJECT_ID"
echo "  • CUSTOM_VISION_ITERATION_NAME: $CUSTOM_VISION_ITERATION_NAME"
echo "  • AZURE_TRANSLATOR_ENDPOINT: $AZURE_TRANSLATOR_ENDPOINT"
echo "  • AZURE_TRANSLATOR_KEY: ****${AZURE_TRANSLATOR_KEY: -4}"
echo "  • AZURE_TRANSLATOR_REGION: $AZURE_TRANSLATOR_REGION"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "  1. Deploy the Analyzer application code via GitHub Actions"
echo "  2. Test the Silver/Gold pipeline with a document upload"
echo ""
echo -e "${GREEN}🎉 Analyzer AI configuration complete!${NC}"
