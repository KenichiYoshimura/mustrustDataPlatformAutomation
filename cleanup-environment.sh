#!/bin/bash
set -e

# MusTrusT Environment Cleanup Script
# Removes all resources for a specific customer/environment

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CUSTOMER_NAME=""
ENVIRONMENT=""
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-6a6d110d-80ef-424a-b8bb-24439063ffb2}"

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
    --subscription)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 --customer <name> --environment <env>"
      echo ""
      echo "Options:"
      echo "  --customer        Customer name"
      echo "  --environment     Environment (dev, test, or prod)"
      echo "  --subscription    Azure subscription ID (optional)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$CUSTOMER_NAME" ]] || [[ -z "$ENVIRONMENT" ]]; then
  echo -e "${RED}❌ Error: Missing required parameters${NC}"
  echo "Use --help for usage information"
  exit 1
fi

RESOURCE_GROUP="rg-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"
SP_NAME="github-mustrust-${CUSTOMER_NAME}-${ENVIRONMENT}"

echo -e "${YELLOW}⚠️  WARNING: This will DELETE the following:${NC}"
echo "  • Resource Group: $RESOURCE_GROUP (and all resources inside)"
echo "  • Service Principal: $SP_NAME"
echo ""
read -p "Are you sure? Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo -e "${BLUE}🗑️  Deleting resources...${NC}"

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Delete resource group
echo "Deleting resource group: $RESOURCE_GROUP"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

# Delete service principal
SP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].id" -o tsv 2>/dev/null)
if [[ -n "$SP_ID" ]]; then
  echo "Deleting service principal: $SP_NAME"
  az ad sp delete --id "$SP_ID"
else
  echo "Service principal not found: $SP_NAME"
fi

echo ""
echo -e "${GREEN}✅ Cleanup initiated${NC}"
echo "Resource group deletion is running in the background."
echo "It may take a few minutes to complete."
