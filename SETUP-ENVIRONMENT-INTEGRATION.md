# setup-environment.sh Integration Guide

**Status:** ✅ Integrated with Phase 1 infrastructure  
**Purpose:** Automated deployment of App Service infrastructure for multiple customers and environments

---

## Overview

The **`setup-environment.sh`** script automates the complete Phase 1 infrastructure deployment for MusTrusT Preprocessor using Bicep templates. It handles:

- ✅ Resource naming conventions (customer + environment)
- ✅ Infrastructure provisioning via `deploy.sh` (which runs Bicep)
- ✅ GitHub Actions service principal creation
- ✅ Credential management for CI/CD

---

## Quick Start

### Basic Usage

```bash
cd /Users/kenichi/Desktop/GitHubMusTrusTDataProjects/MusTrusTDataPlatformInfra

# Deploy Preprocessor infrastructure for YYS Development
./setup-environment.sh --customer yys --environment dev

# Deploy for HCS Production
./setup-environment.sh --customer hcs --environment prod

# Deploy with Analyzer (Silver/Gold layers)
./setup-environment.sh --customer yys --environment dev --with-analyzer
```

### Available Options

```bash
./setup-environment.sh --help
```

| Option | Required | Example | Description |
|--------|----------|---------|-------------|
| `--customer` | ✅ Yes | `yys`, `hcs` | Customer identifier |
| `--environment` | ✅ Yes | `dev`, `test`, `prod` | Deployment environment |
| `--with-analyzer` | ❌ No | (flag) | Deploy Analyzer + Cosmos DB |
| `--github-repo` | ❌ No | `org/repo-name` | GitHub repository for deployments |
| `--subscription` | ❌ No | `uuid` | Azure subscription ID |

---

## What Gets Created

### Resource Naming Convention

All resources follow the naming pattern: `{service}-mustrust-{customer}-{environment}`

**Example for `--customer yys --environment dev`:**

| Resource | Name |
|----------|------|
| Resource Group | `rg-mustrust-yys-dev` |
| App Service Plan | `asp-mustrust-yys-dev` |
| App Service (Preprocessor) | `func-mustrust-preprocessor-yys-dev` |
| App Service (Analyzer, if enabled) | `func-mustrust-analyzer-yys-dev` |
| Web Storage Account | `stmustrustweb-yys-dev` |
| Analyzer Storage Account | `stmustrust-yys-dev` |
| GitHub Service Principal | `github-mustrust-yys-dev` |

### Bicep Infrastructure Deployed

```
bicep/main.bicep (orchestration)
├── bicep/modules/app-service-preprocessor.bicep
│   ├── App Service Plan (S1, Windows, Python 3.11)
│   ├── App Service with Easy Auth
│   ├── Managed Identity
│   ├── Application Insights
│   └── Log Analytics Workspace
├── bicep/modules/storage.bicep
│   ├── Web storage (frontend + uploads)
│   └── Analyzer storage (processing + data)
└── Other modules (networking, monitoring, etc.)
```

**Key Configuration:**
- Platform: Windows (for Easy Auth support)
- SKU: Standard S1 (1 vCPU, 1.75GB RAM, ~$73/month)
- Runtime: Python 3.11
- Always-On: Enabled (no cold starts)
- Easy Auth: Azure AD provider (needs AAD app registration)

---

## Integration with Bicep Templates

### Parameter Flow

```
setup-environment.sh
└── Updates bicep/main.bicepparam with:
    ├── customerName = 'yys'
    ├── environment = 'dev'
    ├── deploySilverGold = false (or true with --with-analyzer)
    └── location = 'japaneast'
    
    └── Calls deploy.sh
        └── Runs Bicep deployment
            └── Creates Azure resources
```

### Updated bicep/main.bicepparam

The script automatically generates this file:

```bicep
using './main.bicep'

param customerName = 'yys'
param environment = 'dev'
param location = 'japaneast'
param storageAccountSku = 'Standard_LRS'
param deploySilverGold = false
```

### Azure AD Configuration

**Important:** Easy Auth requires manual Azure AD app registration. The script guides you through this:

```bash
# After deployment succeeds, the script shows:
❌ Easy Auth requires Azure AD app registration
📝 Create app registration: https://portal.azure.com/#blade/...
📋 Copy these values:
   - Tenant ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   - Client ID: yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
   - Client Secret: zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz

🔧 Configure Easy Auth:
az functionapp config appsettings set \
  --name func-mustrust-preprocessor-yys-dev \
  --resource-group rg-mustrust-yys-dev \
  --settings \
    "AAD_TENANT_ID=<tenant-id>" \
    "AAD_CLIENT_ID=<client-id>" \
    "AAD_CLIENT_SECRET=<client-secret>"
```

---

## GitHub Actions Integration

### Service Principal Creation

The script automatically creates a service principal for GitHub Actions:

```
Service Principal: github-mustrust-yys-dev
├── Permissions: Contributor role on resource group
├── Credentials: Generated and saved to .azure-credentials-yys-dev.json
└── Scope: /subscriptions/{id}/resourceGroups/rg-mustrust-yys-dev
```

### Output Example

```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "6a6d110d-80ef-424a-b8bb-24439063ffb2",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### Adding to GitHub Secrets

1. Copy credentials from `.azure-credentials-{customer}-{environment}.json`
2. Go to repository settings: `Settings → Secrets and variables → Actions`
3. Create secret `AZURE_CREDENTIALS` with the JSON content
4. Delete the credentials file (security best practice)

```bash
# After setup completes:
cat .azure-credentials-yys-dev.json
# Copy to GitHub Secrets
rm .azure-credentials-yys-dev.json
```

---

## Deployment Process

### Step 1: Prerequisites

```bash
# Login to Azure
az login

# Set default subscription
az account set --subscription "6a6d110d-80ef-424a-b8bb-24439063ffb2"

# Verify subscription
az account show
```

### Step 2: Run setup-environment.sh

```bash
cd MusTrusTDataPlatformInfra

./setup-environment.sh --customer yys --environment dev
```

### Step 3: Monitor Deployment

The script shows:
- ✅ Azure CLI login verification
- ✅ Subscription confirmation
- ✅ Resource names to be created
- ✅ Bicep deployment progress
- ✅ Service principal creation
- ✅ GitHub credentials generation

### Step 4: Configure Easy Auth (Manual)

Create Azure AD app registration and configure Easy Auth:

```bash
# Create app registration
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_REG=$(az ad app create \
  --display-name "MusTrusT Preprocessor YYS Dev" \
  --query appId -o tsv)

# Create client secret
CLIENT_SECRET=$(az ad app credential create \
  --id "$APP_REG" \
  --display-name "Auth Secret" \
  --query password -o tsv)

# Configure Easy Auth on App Service
az functionapp config appsettings set \
  --name func-mustrust-preprocessor-yys-dev \
  --resource-group rg-mustrust-yys-dev \
  --settings \
    "AAD_TENANT_ID=$TENANT_ID" \
    "AAD_CLIENT_ID=$APP_REG" \
    "AAD_CLIENT_SECRET=$CLIENT_SECRET"
```

### Step 5: Deploy Application Code

```bash
# Deploy Preprocessor FastAPI app
cd mustrustDataPlatformProcessor
func azure functionapp publish func-mustrust-preprocessor-yys-dev

# Deploy Frontend (static website)
./deploy-frontend.sh stmustrustweb-yys-dev
```

### Step 6: Setup EventGrid (Optional)

```bash
# Configure storage event subscriptions
cd MusTrusTDataPlatformInfra
./setup-eventgrid.sh
```

---

## Multi-Customer / Multi-Environment Deployments

The script enables easy deployment across multiple customers and environments:

### YYS Customer

```bash
./setup-environment.sh --customer yys --environment dev
./setup-environment.sh --customer yys --environment test
./setup-environment.sh --customer yys --environment prod
```

### HCS Customer

```bash
./setup-environment.sh --customer hcs --environment dev
./setup-environment.sh --customer hcs --environment prod
```

### Resource Organization

```
Azure Subscription
├── rg-mustrust-yys-dev
│   ├── func-mustrust-preprocessor-yys-dev
│   ├── stmustrustweb-yys-dev
│   ├── stmustrust-yys-dev
│   └── ...
├── rg-mustrust-yys-test
│   ├── func-mustrust-preprocessor-yys-test
│   └── ...
├── rg-mustrust-yys-prod
│   ├── func-mustrust-preprocessor-yys-prod
│   └── ...
├── rg-mustrust-hcs-dev
│   └── ...
└── rg-mustrust-hcs-prod
    └── ...
```

---

## Comparison: setup-environment.sh vs Manual Deployment

| Aspect | setup-environment.sh | Manual Deployment |
|--------|----------------------|-------------------|
| **Resource naming** | Automatic | Manual |
| **Parameter file** | Auto-generated | Manual edit |
| **Bicep deployment** | Automatic via deploy.sh | Manual az cli |
| **Service principal** | Auto-created | Manual creation |
| **GitHub credentials** | Auto-generated | Manual setup |
| **Time required** | ~5-10 min | ~30+ min |
| **Error-prone** | Low | Higher |
| **Flexibility** | Medium | High |
| **Best for** | Standard deployments | Custom scenarios |

---

## Troubleshooting

### Issue: "Not logged in to Azure CLI"

```bash
az login
az account set --subscription "6a6d110d-80ef-424a-b8bb-24439063ffb2"
```

### Issue: "Service principal already exists"

The script automatically resets credentials:

```
⚠️  Service principal 'github-mustrust-yys-dev' already exists
🔄 Resetting credentials...
✅ Service principal updated
```

### Issue: Bicep deployment fails

Check deploy.sh logs:

```bash
# Validate bicep template
az bicep build --file bicep/main.bicep

# Check for syntax errors
az deployment subscription validate \
  --location japaneast \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

### Issue: Resource group name conflict

Each customer + environment combination has unique names, so conflicts are rare. If they occur:

```bash
# List existing resource groups
az group list --query "[].name" -o table

# Delete conflicting group (if needed)
az group delete --name rg-mustrust-yys-dev --yes
```

---

## References

- [PHASE-1-DEPLOYMENT-GUIDE.md](PHASE-1-DEPLOYMENT-GUIDE.md) — Complete deployment instructions
- [PREPROCESSOR_MIGRATION.md](PREPROCESSOR_MIGRATION.md) — Architecture and migration plan
- [bicep/main.bicep](bicep/main.bicep) — Bicep orchestration template
- [bicep/modules/app-service-preprocessor.bicep](bicep/modules/app-service-preprocessor.bicep) — App Service module
- [deploy.sh](deploy.sh) — Bicep deployment script

---

## Next Steps

1. ✅ Run `setup-environment.sh` to create infrastructure
2. ✅ Create Azure AD app registration (manual)
3. ✅ Configure Easy Auth credentials
4. ⏳ Deploy FastAPI application (Phase 2)
5. ⏳ Test endpoints (Phase 3)
6. ⏳ Production deployment (Phase 4)

