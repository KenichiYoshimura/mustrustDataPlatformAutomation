# Python Function App Deployment Guide

## Overview

This guide shows how to automate deployment of your Python Function App to different environments (dev/test/prod) and customers, matching the parameterized infrastructure setup.

## Deployment Strategy

The GitHub Actions workflow automatically determines the deployment target:

- **Branch-based**: 
  - `main` branch → **prod** environment
  - `develop` branch → **dev** environment
- **Manual trigger**: Choose environment and customer name via GitHub UI

All deployments follow the naming convention:
- Function App: `func-mustrust-preprocessor-{customer}-{env}`
- Resource Group: `rg-mustrust-{customer}-{env}`

Default customer: `yys`

## Prerequisites
- Your Python Function App code in GitHub repository
- Azure CLI installed and authenticated
- Infrastructure already deployed using this repo's Bicep scripts

## Setup GitHub Actions Deployment

### Step 1: Create Azure Service Principal

Run this command to create a service principal for GitHub Actions:

```bash
az ad sp create-for-rbac \
  --name "github-actions-mustrust" \
  --role contributor \
  --scopes /subscriptions/6a6d110d-80ef-424a-b8bb-24439063ffb2/resourceGroups/rg-mustrust-yys-prod \
  --sdk-auth
```

This will output JSON like:
```json
{
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "6a6d110d-80ef-424a-b8bb-24439063ffb2",
  "tenantId": "...",
  ...
}
```

**Copy this entire JSON output** - you'll need it in the next step.

### Step 2: Add GitHub Secret

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AZURE_CREDENTIALS`
5. Value: Paste the entire JSON output from Step 1
6. Click **Add secret**

### Step 3: Setup Your Python App Structure

Your Python Function App repository should have this structure:

```
your-function-repo/
├── .github/
│   └── workflows/
│       └── deploy-function.yml    # Copy from this repo
├── function_app.py                # Your Python code
├── requirements.txt               # Python dependencies
└── host.json                      # Function host configuration
```

**Important**: Default customer is `yys`. Adjust the `CUSTOMER_NAME` in the workflow file (`.github/workflows/deploy-function.yml`) if deploying for different customers.

#### requirements.txt
```
azure-functions
azure-storage-blob
azure-storage-queue
pytz
tenacity
PyMuPDF
Pillow
```

#### host.json
```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

### Step 4: Copy GitHub Actions Workflow

Copy `.github/workflows/deploy-function.yml` from this infrastructure repo to your Python Function App repo.

**Configure the workflow**:
1. Set `CUSTOMER_NAME` to match your deployment (default: 'yys')
2. Adjust `AZURE_FUNCTIONAPP_PACKAGE_PATH` if your code is not in root (default: './')
3. Verify `PYTHON_VERSION` matches your runtime (default: '3.11')

### Step 5: Deploy

**Automatic Deployment:**
- Push to `main` branch → deploys to **prod** (func-mustrust-preprocessor-yys-prod)
- Push to `develop` branch → deploys to **dev** (func-mustrust-preprocessor-yys-dev)

**Manual Deployment:**
1. Go to GitHub → **Actions** tab
2. Select **Deploy Azure Function App** workflow
3. Click **Run workflow**
4. Choose environment (dev/test/prod) and customer name
5. Click **Run workflow**

Monitor deployment at: **GitHub → Actions** tab

---

## Multi-Customer / Multi-Environment Setup

### Option 1: Repository Variables (Recommended)

Set different customer names per environment using GitHub repository variables:

1. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Add variables:
   - `CUSTOMER_NAME` = 'yys' (or other customer)
   - Update workflow to use: `${{ vars.CUSTOMER_NAME }}`

### Option 2: Multiple Service Principals

Create separate service principals for each environment:

```bash
# Dev environment
az ad sp create-for-rbac \
  --name "github-actions-mustrust-dev" \
  --role contributor \
  --scopes /subscriptions/6a6d110d-80ef-424a-b8bb-24439063ffb2/resourceGroups/rg-mustrust-yys-dev \
  --sdk-auth

# Test environment
az ad sp create-for-rbac \
  --name "github-actions-mustrust-test" \
  --role contributor \
  --scopes /subscriptions/6a6d110d-80ef-424a-b8bb-24439063ffb2/resourceGroups/rg-mustrust-yys-test \
  --sdk-auth

# Prod environment  
az ad sp create-for-rbac \
  --name "github-actions-mustrust-prod" \
  --role contributor \
  --scopes /subscriptions/6a6d110d-80ef-424a-b8bb-24439063ffb2/resourceGroups/rg-mustrust-yys-prod \
  --sdk-auth
```

Add as GitHub secrets:
- `AZURE_CREDENTIALS_DEV`
- `AZURE_CREDENTIALS_TEST`
- `AZURE_CREDENTIALS_PROD`

Then modify the workflow to select the appropriate credential based on environment.

### Option 3: Branch Protection

Use GitHub branch protection rules:
- `main` branch → requires approval → deploys to prod
- `develop` branch → auto-deploys to dev
- `release/*` branches → deploys to test

---

## Alternative: Manual Deployment via Azure CLI

If you prefer not to use GitHub Actions:

```bash
# 1. Clone your Python Function App repo
cd /path/to/your/python-function-repo

# 2. Deploy using Azure Functions Core Tools
func azure functionapp publish func-mustrust-preprocessor-yys-prod --python
```

Or using Azure CLI:

```bash
# 1. Create deployment package
cd /path/to/your/python-function-repo
zip -r function-app.zip . -x "*.git*" -x "*__pycache__*" -x "*.venv*"

# 2. Deploy to Azure
az functionapp deployment source config-zip \
  --resource-group rg-mustrust-yys-prod \
  --name func-mustrust-preprocessor-yys-prod \
  --src function-app.zip
```

---

## Verify Deployment

Check deployment status:
```bash
az functionapp show \
  --name func-mustrust-preprocessor-yys-prod \
  --resource-group rg-mustrust-yys-prod \
  --query state
```

View logs:
```bash
az functionapp log tail \
  --name func-mustrust-preprocessor-yys-prod \
  --resource-group rg-mustrust-yys-prod
```

---

## Setup Event Grid Trigger

After deploying your Python code, configure Event Grid to trigger on blob uploads:

```bash
# Get Function App system key
FUNCTION_KEY=$(az functionapp keys list \
  --name func-mustrust-preprocessor-yys-prod \
  --resource-group rg-mustrust-yys-prod \
  --query systemKeys.blobs_extension -o tsv)

# Get Storage Account ID
STORAGE_ID=$(az storage account show \
  --name stmustrustyysprod \
  --resource-group rg-mustrust-yys-prod \
  --query id -o tsv)

# Create Event Grid subscription
az eventgrid event-subscription create \
  --name blob-upload-trigger \
  --source-resource-id $STORAGE_ID \
  --endpoint "https://func-mustrust-preprocessor-yys-prod.azurewebsites.net/runtime/webhooks/EventGrid?functionName=EventGridTrigger&code=$FUNCTION_KEY" \
  --endpoint-type webhook \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with /blobServices/default/containers/bronze-input-files/
```

This will trigger your EventGridTrigger function whenever a file is uploaded to the `bronze-input-files` container.
