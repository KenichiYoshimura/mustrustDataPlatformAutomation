#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Setup Easy Auth for Preprocessor App Service
# Automates Azure AD app registration and Easy Auth configuration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CUSTOMER=""
ENVIRONMENT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --customer)
      CUSTOMER="$2"
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
      echo "  --customer      Customer name (e.g., yys, hcs, abc)"
      echo "  --environment   Environment (dev, test, or prod)"
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

# Validate required arguments
if [ -z "$CUSTOMER" ] || [ -z "$ENVIRONMENT" ]; then
    echo "❌ Missing required arguments"
    echo ""
    echo "Usage: $0 --customer <name> --environment <env>"
    echo ""
    echo "Example: $0 --customer yys --environment dev"
    exit 1
fi

echo "╔════════════════════════════════════════════════╗"
echo "║   Setup Easy Auth for Preprocessor             ║"
echo "╚════════════════════════════════════════════════╝"

# Configuration
APP_NAME="app-mustrust-preprocessor-${CUSTOMER}-${ENVIRONMENT}"
APP_REGISTRATION_NAME="mustrust-preprocessor-${CUSTOMER}-${ENVIRONMENT}"
SECURITY_GROUP_NAME="mustrust-${CUSTOMER}-${ENVIRONMENT}-users"
RESOURCE_GROUP="rg-mustrust-${CUSTOMER}-${ENVIRONMENT}"
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_DOMAIN="https://${APP_NAME}.azurewebsites.net"

echo "Configuration:"
echo "  Customer:           $CUSTOMER"
echo "  Environment:        $ENVIRONMENT"
echo "  App Service:        $APP_NAME"
echo "  App Registration:   $APP_REGISTRATION_NAME"
echo "  Security Group:     $SECURITY_GROUP_NAME"
echo "  Resource Group:     $RESOURCE_GROUP"
echo "  Tenant ID:          $TENANT_ID"
echo "  Domain:             $APP_DOMAIN"
echo ""

# Check if resource group exists
echo "🔍 Checking resource group..."
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "❌ Resource group $RESOURCE_GROUP not found"
    exit 1
fi
echo "✅ Resource group found"

# Check if app service exists
echo "🔍 Checking App Service..."
if ! az webapp show --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" &>/dev/null; then
    echo "❌ App Service $APP_NAME not found"
    exit 1
fi
echo "✅ App Service found"

# Create or verify Azure AD security group
echo ""
echo "👥 Setting up Azure AD security group..."
EXISTING_GROUP=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null)

if [[ -n "$EXISTING_GROUP" ]]; then
    echo "✅ Security group already exists: $SECURITY_GROUP_NAME"
    GROUP_ID="$EXISTING_GROUP"
else
    echo "📝 Creating security group..."
    GROUP_ID=$(az ad group create \
        --display-name "$SECURITY_GROUP_NAME" \
        --mail-nickname "${CUSTOMER}-${ENVIRONMENT}-users" \
        --description "Users allowed to access MusTrusT Data Platform for ${CUSTOMER} ${ENVIRONMENT}" \
        --query id -o tsv)
    echo "✅ Security group created: $SECURITY_GROUP_NAME"
fi

echo "   Group Object ID: $GROUP_ID"
echo ""
echo "⚠️  TODO: Add users to the security group:"
echo "   az ad group member add --group \"$SECURITY_GROUP_NAME\" --member-id <USER_OBJECT_ID>"
echo ""

# Check if app registration already exists
echo "🔍 Checking for existing app registration..."
EXISTING_APP=$(az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ] && [ "$EXISTING_APP" != "None" ]; then
    echo "⚠️  App registration '$APP_REGISTRATION_NAME' already exists"
    echo "   ID: $EXISTING_APP"
    read -p "   Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    APP_ID=$EXISTING_APP
else
    # Create new app registration
    echo "📝 Creating app registration..."
    APP_ID=$(az ad app create \
        --display-name "$APP_REGISTRATION_NAME" \
        --query id -o tsv)
    echo "✅ App registration created: $APP_ID"
fi

# Set up redirect URIs
echo "🌐 Configuring redirect URIs..."
REDIRECT_URIS=(
    "${APP_DOMAIN}/.auth/login/aad/callback"
    "${APP_DOMAIN}/"
    "http://localhost:3000/.auth/login/aad/callback"
    "http://localhost:3000/"
)

az ad app update --id "$APP_ID" \
    --web-redirect-uris "${REDIRECT_URIS[@]}" \
    --enable-id-token-issuance true \
    --enable-access-token-issuance true

echo "✅ Redirect URIs configured"

# Configure group membership claims
echo "👥 Configuring group membership claims..."
az ad app update --id "$APP_ID" \
    --set groupMembershipClaims=SecurityGroup

echo "✅ Group membership claims configured"

# Create service principal if it doesn't exist
echo "🔑 Checking service principal..."
SP_ID=$(az ad sp list --display-name "$APP_REGISTRATION_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -z "$SP_ID" ] || [ "$SP_ID" = "None" ]; then
    echo "📝 Creating service principal..."
    SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
    echo "✅ Service principal created: $SP_ID"
else
    echo "✅ Service principal already exists: $SP_ID"
fi

# Create client secret
echo "🔐 Creating client secret..."
EXPIRY_DATE=$(date -v+2y +%Y-%m-%d 2>/dev/null || date -d "+2 years" +%Y-%m-%d)
SECRET=$(az ad app credential reset \
    --id "$APP_ID" \
    --display-name "Easy Auth Secret" \
    --end-date "$EXPIRY_DATE" \
    --query password -o tsv)

if [ -z "$SECRET" ]; then
    echo "❌ Failed to create client secret"
    exit 1
fi
echo "✅ Client secret created"

# Get client ID
CLIENT_ID=$(az ad app show --id "$APP_ID" --query appId -o tsv)

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Credentials Generated                        ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "📋 Save these credentials securely:"
echo ""
echo "  Tenant ID:      $TENANT_ID"
echo "  Client ID:      $CLIENT_ID"
echo "  Client Secret:  ${SECRET:0:10}...${SECRET: -10}"
echo ""
echo "⚙️  Configuring App Service..."

# Update App Service with Easy Auth settings
az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --settings \
    AZURE_AD_CLIENT_ID="$CLIENT_ID" \
    AZURE_AD_CLIENT_SECRET="$SECRET" \
    AZURE_AD_TENANT_ID="$TENANT_ID" \
    ALLOWED_AAD_GROUPS="$GROUP_ID"

echo "✅ App Service settings updated (including ALLOWED_AAD_GROUPS)"

# Update Easy Auth configuration
echo "🔐 Updating Easy Auth configuration..."
# Explicitly set Azure AD registration (clientId + issuer) and global validation
az webapp auth update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --enabled true \
    --unauthenticated-client-action RedirectToLoginPage \
    --redirect-provider AzureActiveDirectory \
    --set "platform.enabled=true" \
    --set "globalValidation.requireAuthentication=false" \
    --set "globalValidation.redirectToProvider=AzureActiveDirectory" \
    --set "identityProviders.azureActiveDirectory.enabled=true" \
    --set "identityProviders.azureActiveDirectory.registration.clientId=$CLIENT_ID" \
    --set "identityProviders.azureActiveDirectory.registration.openIdIssuer=https://login.microsoftonline.com/$TENANT_ID/v2.0" \
    --set "identityProviders.azureActiveDirectory.registration.clientSecretSettingName=AZURE_AD_CLIENT_SECRET"

# Show applied auth settings for verification
echo "🔎 Current authsettingsV2:"
az webapp auth show --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" -o json | jq '{globalValidation: .globalValidation, identityProviders: .identityProviders}' || true

echo "✅ Easy Auth configured"

# Restart app
echo "🔄 Restarting app service..."
az webapp restart --resource-group "$RESOURCE_GROUP" --name "$APP_NAME"
echo "✅ App service restarted"

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Easy Auth Setup Complete!                    ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "✅ Your app is now secured with Easy Auth!"
echo ""
echo "📊 Configuration Summary:"
echo "   App Registration:   $APP_REGISTRATION_NAME"
echo "   Client ID:          $CLIENT_ID"
echo "   Security Group:     $SECURITY_GROUP_NAME"
echo "   Group Object ID:    $GROUP_ID"
echo ""
echo "🧪 Test it:"
echo "   1. Open: $APP_DOMAIN"
echo "   2. You should be redirected to Azure AD login"
echo "   3. After login, you can access the app"
echo ""
echo "⚠️  IMPORTANT - Add Users to Security Group:"
echo "   # Get user's Object ID"
echo "   az ad user show --id \"user@domain.com\" --query id -o tsv"
echo ""
echo "   # Add user to group"
echo "   az ad group member add --group \"$SECURITY_GROUP_NAME\" --member-id <USER_OBJECT_ID>"
echo ""
echo "📝 For production, verify Easy Auth in Azure Portal:"
echo "   https://portal.azure.com → App Service → $APP_NAME → Authentication"
echo ""
