#!/bin/bash

# Verify Analyzer Function App Configuration
# This script extracts and compares app settings between two Analyzer environments

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
CUSTOMER=""
ENV1=""
ENV2=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --customer)
      CUSTOMER="$2"
      shift 2
      ;;
    --env1)
      ENV1="$2"
      shift 2
      ;;
    --env2)
      ENV2="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 --customer <name> [--env1 <env>] [--env2 <env>]"
      echo ""
      echo "Options:"
      echo "  --customer    Customer name (e.g., yys, hcs)"
      echo "  --env1        First environment (default: dev)"
      echo "  --env2        Second environment (default: prod)"
      echo ""
      echo "Examples:"
      echo "  $0 --customer yys                    # Compare dev and prod"
      echo "  $0 --customer yys --env1 dev --env2 test"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Set defaults
ENV1="${ENV1:-dev}"
ENV2="${ENV2:-prod}"

if [[ -z "$CUSTOMER" ]]; then
  echo -e "${RED}❌ Error: --customer is required${NC}"
  echo "Use --help for usage information"
  exit 1
fi

# Resource names
RG1="rg-mustrust-${CUSTOMER}-${ENV1}"
RG2="rg-mustrust-${CUSTOMER}-${ENV2}"
APP1="func-mustrust-analyzer-${CUSTOMER}-${ENV1}"
APP2="func-mustrust-analyzer-${CUSTOMER}-${ENV2}"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Analyzer Configuration Verification         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Comparing:${NC}"
echo "  Environment 1: $ENV1 ($APP1)"
echo "  Environment 2: $ENV2 ($APP2)"
echo ""

# Required settings
REQUIRED_SETTINGS=(
  "DOCUMENT_INTELLIGENCE_ENDPOINT"
  "DOCUMENT_INTELLIGENCE_KEY"
  "CLASSIFIER_ENDPOINT"
  "CLASSIFIER_ENDPOINT_AZURE_API_KEY"
  "CLASSIFIER_ID"
  "BANK_DOCUMENT_INTELLIGENCE_ENDPOINT"
  "BANK_DOCUMENT_INTELLIGENCE_KEY"
  "BANK_CUSTOM_MODEL_ID"
  "BANK_CUSTOM_VISION_ENDPOINT"
  "BANK_CUSTOM_VISION_PREDICTION_KEY"
  "BANK_CUSTOM_VISION_PROJECT_ID"
  "BANK_CUSTOM_VISION_ITERATION_NAME"
  "CUSTOM_VISION_PREDICTION_ENDPOINT"
  "CUSTOM_VISION_PREDICTION_KEY"
  "CUSTOM_VISION_ENDPOINT"
  "CUSTOM_VISION_KEY"
  "CUSTOM_VISION_PROJECT_ID"
  "CUSTOM_VISION_ITERATION_NAME"
  "COSMOS_DB_CONNECTION_STRING"
  "COSMOS_DB_DATABASE_NAME"
  "COSMOS_DB_SILVER_CONTAINER"
  "COSMOS_DB_GOLD_CONTAINER"
  "LANGUAGE_SERVICE_ENDPOINT"
  "LANGUAGE_SERVICE_KEY"
  "AZURE_LANGUAGE_ENDPOINT"
  "AZURE_LANGUAGE_KEY"
  "AZURE_TRANSLATOR_ENDPOINT"
  "AZURE_TRANSLATOR_KEY"
  "AZURE_TRANSLATOR_REGION"
)

# Get settings from both apps
echo -e "${BLUE}📥 Retrieving settings from $ENV1...${NC}"
SETTINGS1=$(az functionapp config appsettings list \
  --name "$APP1" \
  --resource-group "$RG1" \
  --output json 2>/dev/null)

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to retrieve settings from $APP1${NC}"
  echo "  Make sure the function app exists and you have access"
  exit 1
fi

echo -e "${BLUE}📥 Retrieving settings from $ENV2...${NC}"
SETTINGS2=$(az functionapp config appsettings list \
  --name "$APP2" \
  --resource-group "$RG2" \
  --output json 2>/dev/null)

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to retrieve settings from $APP2${NC}"
  echo "  Make sure the function app exists and you have access"
  exit 1
fi

echo ""

# Extract all setting names from both environments
ALL_SETTINGS_1=($(echo "$SETTINGS1" | jq -r '.[].name' | sort -u))
ALL_SETTINGS_2=($(echo "$SETTINGS2" | jq -r '.[].name' | sort -u))

# Combine and deduplicate
ALL_SETTINGS=($(printf '%s\n' "${ALL_SETTINGS_1[@]}" "${ALL_SETTINGS_2[@]}" | sort -u))

echo -e "${BLUE}📊 Total unique settings found:${NC}"
echo "  $ENV1: ${#ALL_SETTINGS_1[@]} settings"
echo "  $ENV2: ${#ALL_SETTINGS_2[@]} settings"
echo "  Combined: ${#ALL_SETTINGS[@]} unique settings"
echo ""

echo -e "${BLUE}🔍 Checking required settings...${NC}"
echo ""

MISSING_COUNT=0
MISMATCH_COUNT=0
OK_COUNT=0

for SETTING in "${REQUIRED_SETTINGS[@]}"; do
  VALUE1=$(echo "$SETTINGS1" | jq -r ".[] | select(.name==\"$SETTING\") | .value" 2>/dev/null)
  VALUE2=$(echo "$SETTINGS2" | jq -r ".[] | select(.name==\"$SETTING\") | .value" 2>/dev/null)
  
  # Check if setting exists in both
  if [[ -z "$VALUE1" ]] && [[ -z "$VALUE2" ]]; then
    echo -e "${RED}❌ $SETTING${NC}"
    echo "   Missing in both environments"
    ((MISSING_COUNT++))
  elif [[ -z "$VALUE1" ]]; then
    echo -e "${YELLOW}⚠️  $SETTING${NC}"
    echo "   Missing in $ENV1"
    ((MISSING_COUNT++))
  elif [[ -z "$VALUE2" ]]; then
    echo -e "${YELLOW}⚠️  $SETTING${NC}"
    echo "   Missing in $ENV2"
    ((MISSING_COUNT++))
  else
    # Both exist, check if they should match
    # Keys and connection strings should be masked
    if [[ "$SETTING" == *"KEY"* ]] || [[ "$SETTING" == *"CONNECTION_STRING"* ]]; then
      MASK1="****${VALUE1: -4}"
      MASK2="****${VALUE2: -4}"
      echo -e "${GREEN}✅ $SETTING${NC}"
      echo "   $ENV1: $MASK1"
      echo "   $ENV2: $MASK2"
    else
      # Check if this setting is expected to differ between environments
      # LANGUAGE_SERVICE_ENDPOINT, AZURE_LANGUAGE_ENDPOINT and COSMOS_DB_* are environment-specific
      if [[ "$SETTING" == "LANGUAGE_SERVICE_ENDPOINT" ]] || [[ "$SETTING" == "AZURE_LANGUAGE_ENDPOINT" ]] || [[ "$SETTING" == "COSMOS_DB_CONNECTION_STRING" ]]; then
        echo -e "${GREEN}✅ $SETTING${NC}"
        echo "   $ENV1: $VALUE1"
        echo "   $ENV2: $VALUE2"
        echo "   (Environment-specific - different values expected)"
      elif [[ "$VALUE1" == "$VALUE2" ]]; then
        echo -e "${GREEN}✅ $SETTING${NC}"
        echo "   Value: $VALUE1"
      else
        echo -e "${YELLOW}⚠️  $SETTING${NC}"
        echo "   $ENV1: $VALUE1"
        echo "   $ENV2: $VALUE2"
        echo "   (Different values - verify if this is intended)"
        ((MISMATCH_COUNT++))
      fi
    fi
    ((OK_COUNT++))
  fi
  echo ""
done

# Check for extra settings not in required list
echo -e "${BLUE}🔍 Checking for additional settings not in required list...${NC}"
echo ""

EXTRA_COUNT=0
for SETTING in "${ALL_SETTINGS[@]}"; do
  # Check if this setting is in the required list
  IS_REQUIRED=false
  for REQ in "${REQUIRED_SETTINGS[@]}"; do
    if [[ "$SETTING" == "$REQ" ]]; then
      IS_REQUIRED=true
      break
    fi
  done
  
  if [[ "$IS_REQUIRED" == false ]]; then
    VALUE1=$(echo "$SETTINGS1" | jq -r ".[] | select(.name==\"$SETTING\") | .value" 2>/dev/null)
    VALUE2=$(echo "$SETTINGS2" | jq -r ".[] | select(.name==\"$SETTING\") | .value" 2>/dev/null)
    
    # Show where this setting exists
    if [[ -n "$VALUE1" ]] && [[ -n "$VALUE2" ]]; then
      echo -e "${GREEN}ℹ️  $SETTING${NC}"
      echo "   Present in both environments"
    elif [[ -n "$VALUE1" ]]; then
      echo -e "${YELLOW}ℹ️  $SETTING${NC}"
      echo "   Only in $ENV1"
    elif [[ -n "$VALUE2" ]]; then
      echo -e "${YELLOW}ℹ️  $SETTING${NC}"
      echo "   Only in $ENV2"
    fi
    ((EXTRA_COUNT++))
    echo ""
  fi
done

if [ $EXTRA_COUNT -eq 0 ]; then
  echo -e "${GREEN}No additional settings found${NC}"
  echo ""
fi

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Summary                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Configured:  $OK_COUNT/${#REQUIRED_SETTINGS[@]}${NC}"

if [ $EXTRA_COUNT -gt 0 ]; then
  echo -e "${BLUE}ℹ️  Additional:  $EXTRA_COUNT settings (not in required list)${NC}"
fi

if [ $MISSING_COUNT -gt 0 ]; then
  echo -e "${RED}❌ Missing:     $MISSING_COUNT${NC}"
fi

if [ $MISMATCH_COUNT -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Mismatches:  $MISMATCH_COUNT${NC}"
fi

echo ""

if [ $MISSING_COUNT -eq 0 ] && [ $MISMATCH_COUNT -eq 0 ]; then
  echo -e "${GREEN}🎉 All required settings are configured correctly!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Some settings need attention${NC}"
  echo ""
  echo "To configure missing settings, run:"
  if [ $MISSING_COUNT -gt 0 ]; then
    echo "  ./configure-analyzer-ai.sh --customer $CUSTOMER --environment $ENV1"
    echo "  ./configure-analyzer-ai.sh --customer $CUSTOMER --environment $ENV2"
  fi
  exit 1
fi
