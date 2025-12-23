# Phase 1: App Service Infrastructure Deployment Guide

**Status:** ✅ Complete - Infrastructure code ready for deployment  
**Timeframe:** 1-2 hours  
**Deliverable:** Windows App Service Standard S1 infrastructure with Easy Auth configured

**Primary Tool:** `setup-environment.sh` (automated deployment script)

---

## Overview

Phase 1 deploys the Bicep infrastructure for the new Preprocessor on **Azure App Service Standard S1 (Windows)** with:
- ✅ Python 3.11 runtime
- ✅ Easy Auth enabled (Azure AD integration)
- ✅ Managed Identity for secure resource access
- ✅ Application Insights monitoring
- ✅ Autoscaling configured (2-5 instances)
- ✅ Always-On enabled (no cold starts)

This guide shows both **automated** (recommended) and **manual** deployment approaches.

---

## Files Created

### 1. **`bicep/modules/app-service-preprocessor.bicep`** (New)

Complete App Service module with:
- App Service Plan (Standard S1, Windows, single instance with scale capability)
- App Service with Python 3.11 runtime
- Gunicorn worker configuration (3-5 workers for S1)
- Easy Auth configuration (Azure AD integration)
- Managed Identity assignment
- Application Insights integration
- 50MB file upload limit enforcement
- CORS configuration for frontend

### 2. **`bicep/main.bicep`** (Updated)

Added:
- **3 new parameters** for Easy Auth configuration:
  - `deployAppServicePreprocessor` (bool flag)
  - `aadTenantId` (Azure AD tenant ID)
  - `aadClientId` (App registration client ID)
  - `aadClientSecret` (App registration client secret)
- **New variable** for App Service name: `appServicePreprocessorName`
- **Module deployment** block with conditional deployment
- **4 new outputs** for App Service URL, name, Managed Identity, and App Insights

### 3. **`bicep/main.bicepparam`** (Updated)

Added:
- `deployAppServicePreprocessor = false` (disabled by default)
- `aadTenantId = ''` (placeholder, needs actual value)
- `aadClientId = ''` (placeholder, needs actual value)
- `aadClientSecret = ''` (placeholder, needs actual value)

### 4. **`bicep/modules/storage.bicep`** (Updated)

Added:
- **New output**: `accountKey` (storage account key for analyzer access)

---

## Automated Deployment (Recommended)

Use the **`setup-environment.sh`** script to automate the entire Phase 1 deployment:

```bash
cd /Users/kenichi/Desktop/GitHubMusTrusTDataProjects/MusTrusTDataPlatformInfra

# Basic deployment (Preprocessor only)
./setup-environment.sh \
  --customer yys \
  --environment dev

# Or with Analyzer (Silver/Gold layers)
./setup-environment.sh \
  --customer yys \
  --environment dev \
  --with-analyzer
```

**What `setup-environment.sh` does:**

1. ✅ Validates Azure CLI login
2. ✅ Sets subscription
3. ✅ Updates bicep/main.bicepparam with customer/environment names
4. ✅ Runs full infrastructure deployment
5. ✅ Creates GitHub Actions service principal
6. ✅ Generates Azure credentials file
7. ✅ Shows next steps (GitHub secrets, code deployment, EventGrid)

**Output:**

After successful deployment, you'll see:
- ✅ Resource Group created: `rg-mustrust-{customer}-{environment}`
- ✅ App Service created: `func-mustrust-preprocessor-{customer}-{environment}`
- ✅ Storage accounts, networking, monitoring configured
- ✅ Service principal with GitHub Actions credentials
- ✅ Detailed next steps for code deployment

**Options:**

```bash
./setup-environment.sh --help
```

Parameters:
- `--customer <name>` — Customer identifier (e.g., yys, hcs) [REQUIRED]
- `--environment <env>` — Deployment environment (dev, test, prod) [REQUIRED]
- `--with-analyzer` — Also deploy Cosmos DB and Analyzer Function App
- `--github-repo <owner/repo>` — GitHub repository for deployment
- `--subscription <id>` — Azure subscription ID (optional)

---

## Manual Deployment (Alternative)

If you prefer to deploy manually or need more control, follow these steps:

### Manual Deployment Prerequisites

### 1. Azure Subscription & CLI

```bash
# Install Azure CLI if not already installed
# macOS: brew install azure-cli
# Or update: brew upgrade azure-cli

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Verify subscription
az account show
```

### 2. Create Azure AD App Registration

This is required for Easy Auth to work. Follow these steps:

**Option A: Using Azure Portal**

1. Go to [Azure AD App registrations](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. Click **New registration**
3. Name: `MusTrusT Preprocessor`
4. Supported account types: **Accounts in this organizational directory only**
5. Redirect URI: `https://<app-service-url>/.auth/login/aad/callback`
   - You'll get this URL after deploying (or use placeholder)
6. Click **Register**

7. Once created, you'll see:
   - **Application (client) ID** → copy to `aadClientId`
   - **Directory (tenant) ID** → copy to `aadTenantId`

8. Go to **Certificates & secrets**
9. Click **New client secret**
10. Description: `MusTrusT Preprocessor Auth`
11. Expires: 24 months
12. Click **Add**
13. Copy the secret value → save to `aadClientSecret`

**Option B: Using Azure CLI**

```bash
# Create app registration
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_REGISTRATION=$(az ad app create \
  --display-name "MusTrusT Preprocessor" \
  --query appId -o tsv)

# Create client secret
CLIENT_SECRET=$(az ad app credential create \
  --id "$APP_REGISTRATION" \
  --display-name "Preprocessor Auth Secret" \
  --query password -o tsv)

# Save these values
echo "TENANT_ID: $TENANT_ID"
echo "CLIENT_ID: $APP_REGISTRATION"
echo "CLIENT_SECRET: $CLIENT_SECRET"
```

### 3. Set Easy Auth Redirect URI

After deploying (you'll have the App Service URL), update the redirect URI:

**Portal:**
1. Go to your app registration
2. **Authentication** → **Platform configurations**
3. **Web** → **Redirect URIs**
4. Add: `https://<your-app-service-name>.azurewebsites.net/.auth/login/aad/callback`
5. Click **Save**

**CLI:**
```bash
az ad app update \
  --id "<client-id>" \
  --web-redirect-uris "https://<your-app-service-name>.azurewebsites.net/.auth/login/aad/callback"
```

---

## Manual Deployment Steps

### Step 1: Prepare Parameters

Edit `bicep/main.bicepparam`:

```bicep
// Set deployment flag to true
param deployAppServicePreprocessor = true

// Set Azure AD values from app registration
param aadTenantId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'        // From Azure AD
param aadClientId = 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'        // From app registration
param aadClientSecret = 'your-client-secret-here'                 // From Certificates & secrets
```

### Step 2: Validate Bicep (Optional but Recommended)

```bash
# Change to the infrastructure directory
cd /Users/kenichi/Desktop/GitHubMusTrusTDataProjects/MusTrusTDataPlatformInfra

# Validate the Bicep template
az bicep build --file bicep/main.bicep

# Or validate with parameters
az deployment subscription validate \
  --location japaneast \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

### Step 3: Deploy Infrastructure

```bash
# Deploy using bicep parameters file
az deployment subscription create \
  --name "mustrust-preprocessor-appservice-$(date +%s)" \
  --location japaneast \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam

# Or with explicit parameters (for testing)
az deployment subscription create \
  --name "mustrust-preprocessor-appservice-$(date +%s)" \
  --location japaneast \
  --template-file bicep/main.bicep \
  --parameters \
    customerName=yys \
    environment=dev \
    location=japaneast \
    storageAccountSku=Standard_LRS \
    deploySilverGold=true \
    deployAppServicePreprocessor=true \
    aadTenantId='<your-tenant-id>' \
    aadClientId='<your-client-id>' \
    aadClientSecret='<your-client-secret>'
```

### Step 4: Capture Deployment Outputs

After deployment completes, capture the outputs:

```bash
# Get deployment outputs
OUTPUTS=$(az deployment subscription show \
  --name "mustrust-preprocessor-appservice-$(date +%s)" \
  --query properties.outputs -o json)

echo "$OUTPUTS" | jq .

# Extract specific values
APP_SERVICE_NAME=$(echo "$OUTPUTS" | jq -r '.appServicePreprocessorName.value')
APP_SERVICE_URL=$(echo "$OUTPUTS" | jq -r '.appServicePreprocessorUrl.value')
MANAGED_IDENTITY=$(echo "$OUTPUTS" | jq -r '.appServiceManagedIdentityId.value')

echo "App Service Name: $APP_SERVICE_NAME"
echo "App Service URL: $APP_SERVICE_URL"
echo "Managed Identity ID: $MANAGED_IDENTITY"
```

---

## Verification Checklist

After deployment, verify that everything is working:

### ✅ Resource Group Created
```bash
az group show \
  --name rg-mustrust-yys-dev \
  --query "{name: name, location: location, state: properties.provisioningState}"
```

### ✅ App Service Running
```bash
# Check app service exists
az webapp show \
  --resource-group rg-mustrust-yys-dev \
  --name app-mustrust-preprocessor-yys-dev

# Check runtime stack
az webapp config show \
  --resource-group rg-mustrust-yys-dev \
  --name app-mustrust-preprocessor-yys-dev \
  --query "[pythonVersion, appCommandLine]"
```

### ✅ Easy Auth Enabled
```bash
# Check Easy Auth status
az rest --method get \
  --url /subscriptions/{subscription-id}/resourceGroups/rg-mustrust-yys-dev/providers/Microsoft.Web/sites/app-mustrust-preprocessor-yys-dev/config/authsettingsv2?api-version=2023-12-01 \
  | jq '.properties.platform.enabled'

# Should return: true
```

### ✅ Managed Identity Created
```bash
# Get managed identity details
az identity show \
  --resource-group rg-mustrust-yys-dev \
  --name app-mustrust-preprocessor-yys-dev-identity
```

### ✅ Application Insights Connected
```bash
# Check App Insights is working
az monitor app-insights component show \
  --resource-group rg-mustrust-yys-dev \
  --app app-mustrust-preprocessor-yys-dev-insights
```

### ✅ Easy Auth /.auth/me Endpoint (Test Easy Auth)

First, deploy placeholder code to App Service, then:

```bash
# Test /.auth/me endpoint (should return 401 if not logged in)
curl -X GET "https://app-mustrust-preprocessor-yys-dev.azurewebsites.net/.auth/me" \
  -H "Accept: application/json"

# Expected response:
# HTTP 401 Unauthorized (no session cookie)
# or
# HTTP 200 with user principal info (if cookie present)
```

---

## Infrastructure Architecture

```
┌─────────────────────────────────────────────────────┐
│  Resource Group: rg-mustrust-yys-dev                │
│  Location: Japan East                               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────┐     │
│  │  App Service Plan (Standard S1, Windows)  │     │
│  │  SKU: S1 (1.75GB RAM, 1 vCPU)            │     │
│  │  Instances: 1 (scales to 10+ if needed)   │     │
│  │  Always On: Enabled (no cold starts)     │     │
│  └───────────────────────────────────────────┘     │
│           │                                         │
│           ├─ App Service (Windows)                 │
│           │  • Runtime: Python 3.11                │
│           │  • Gunicorn: 3-5 workers               │
│           │  • Upload limit: 50MB                  │
│           │  • HTTPs only: Enabled                 │
│           │  • URL: https://app-mustrust-...      │
│           │                                        │
│           └─ Easy Auth (Azure AD)                  │
│              • Tenant: <aadTenantId>              │
│              • Client ID: <aadClientId>           │
│              • Provider: Azure Active Directory    │
│              • /.auth/me: Endpoint                │
│              • X-MS-CLIENT-PRINCIPAL: Injected   │
│                                                    │
│  ┌───────────────────────────────────────────┐    │
│  │  Managed Identity                         │    │
│  │  • Name: app-mustrust-...-identity        │    │
│  │  • Type: User Assigned                    │    │
│  │  • Roles: Storage Blob Reader/Writer      │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  ┌───────────────────────────────────────────┐    │
│  │  Application Insights                     │    │
│  │  • Workspace: app-mustrust-...-logs       │    │
│  │  • Retention: 30 days                     │    │
│  │  • Monitoring: Requests, Dependencies     │    │
│  │  • Logging: Application Insights SDK      │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  ┌───────────────────────────────────────────┐    │
│  │  Storage Account References (Existing)    │    │
│  │  • Bronze: stmustrust{cust}{env}         │    │
│  │  • Queue: bronze-processing              │    │
│  │  • Connection: Managed Identity           │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
└─────────────────────────────────────────────────────┘
```

---

## Post-Deployment Configuration

### Step 1: Deploy Placeholder Application

Before testing Easy Auth, you need to deploy code that responds to HTTP requests.

Create a minimal `main.py` for initial testing:

```python
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()

@app.get("/.auth/me")
async def auth_me(request: Request):
    """Check if user is authenticated"""
    user_id = request.headers.get("X-MS-CLIENT-PRINCIPAL-ID")
    user_name = request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME")
    
    if user_id:
        return {
            "status": "authenticated",
            "userId": user_id,
            "userName": user_name
        }
    else:
        return JSONResponse(
            status_code=401,
            content={"status": "not-authenticated"}
        )

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok"}

@app.post("/api/upload")
async def upload_file():
    """Placeholder upload endpoint"""
    return {"status": "upload-endpoint-ready"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### Step 2: Deploy Code to App Service

#### Option A: ZIP Deploy (Recommended)

```bash
# From Preprocessor project root
cd /Users/kenichi/Desktop/GitHubMusTrusTDataProjects/mustrustDataPlatformProcessor

# Create requirements.txt if not present
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
gunicorn==21.2.0
python-multipart==0.0.6
azure-storage-blob==12.17.0
azure-storage-queue==12.13.0
fitz==0.0.1
PyMuPDF==1.23.8
Pillow==10.0.1
requests==2.31.0
tenacity==8.2.3
EOF

# Create ZIP deployment
rm -f deployment.zip
zip -r deployment.zip main.py requirements.txt -x ".*" "*.git*"

# Deploy to App Service
RESOURCE_GROUP="rg-mustrust-yys-dev"
APP_SERVICE="app-mustrust-preprocessor-yys-dev"

az webapp deployment source config-zip \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_SERVICE" \
  --src deployment.zip
```

#### Option B: Using Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Find your App Service
3. **Deployment Center** → **Settings**
4. Choose **ZIP Deploy**
5. Upload the ZIP file

### Step 3: Configure App Settings

Update app settings for your environment:

```bash
az webapp config appsettings set \
  --resource-group rg-mustrust-yys-dev \
  --name app-mustrust-preprocessor-yys-dev \
  --settings \
    ANALYZER_FUNCTION_URL="https://func-mustrust-analyzer-yys-dev.azurewebsites.net" \
    ANALYZER_QUEUE_NAME="bronze-processing" \
    STORAGE_ACCOUNT_NAME="stmustrustyysdev" \
    ENVIRONMENT="dev" \
    LOG_LEVEL="INFO"
```

---

## Next Steps

After Phase 1 deployment completes:

✅ Phase 1 Outputs:
- Resource Group created
- App Service Plan (S1, Windows) ready
- App Service with Python 3.11 runtime
- Managed Identity assigned
- Easy Auth configured and enabled
- Application Insights ready
- Autoscaling rules configured

**➡️ Phase 2:** Implement FastAPI application
- Create main.py with all endpoints
- Implement POST /api/upload
- Implement 10 proxy endpoints
- Deploy to App Service

**➡️ Phase 3:** Configure Easy Auth
- Test /.auth/me endpoint
- Verify X-MS-CLIENT-PRINCIPAL headers
- Test identity normalization

**➡️ Phase 4:** Frontend testing
- Test all proxy endpoints
- Verify no code changes needed to frontend
- Load testing

**➡️ Phase 5:** Production deployment
- Performance validation
- Monitoring configuration
- Production cutover

---

## Troubleshooting

### Problem: Deployment Fails with "Invalid parameters"

**Solution:**
- Verify all parameter values are correct
- Check that `aadTenantId`, `aadClientId`, `aadClientSecret` are valid
- Ensure Azure AD app registration exists

### Problem: Easy Auth returns 404

**Solution:**
- Verify App Service is Windows-based (not Linux)
- Check Easy Auth is enabled: `az rest --method get ... | jq '.properties.platform.enabled'`
- Make sure code is deployed (App Service needs to be responding to HTTP)
- Check redirect URI is registered in Azure AD

### Problem: Code deployment fails

**Solution:**
- Check Python version: `az webapp config show ... | jq '.pythonVersion'`
- Verify requirements.txt exists and is valid
- Check gunicorn is in requirements.txt
- Review deployment logs: `az webapp deployment logs show ...`

### Problem: Managed Identity permissions missing

**Solution:**
- Assign Managed Identity roles to storage account
- Assign roles to queue
- Use role "Storage Blob Data Contributor" for Managed Identity

---

## Configuration Files Summary

| File | Changes | Purpose |
|------|---------|---------|
| `bicep/modules/app-service-preprocessor.bicep` | New (Created) | App Service Standard S1 infrastructure |
| `bicep/main.bicep` | Updated | Added module reference and new parameters |
| `bicep/main.bicepparam` | Updated | Added Easy Auth configuration placeholders |
| `bicep/modules/storage.bicep` | Updated | Added accountKey output |

---

## Estimated Costs

| Resource | Tier | Monthly Cost |
|----------|------|--------------|
| **App Service Plan** | Standard S1 | ~$73 |
| **Application Insights** | Pay-as-you-go | ~$10-15 |
| **Storage (existing)** | Standard LRS | Already deployed |
| **Managed Identity** | Free | $0 |
| **Total (New)** | | **~$83-88/month** |

---

## Success Criteria - Phase 1

✅ Deployment completed without errors  
✅ Resource Group created
✅ App Service Plan (S1, Windows) created
✅ App Service running Python 3.11
✅ Easy Auth enabled and configured  
✅ Managed Identity created and assigned  
✅ Application Insights monitoring enabled  
✅ Health check endpoint responding (after code deploy)  
✅ /.auth/me endpoint returning proper responses  
✅ All outputs captured for Phase 2  

---

**Phase 1 Status:** Ready for deployment ✅
