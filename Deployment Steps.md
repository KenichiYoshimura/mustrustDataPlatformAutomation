# MusTrusT Data Platform - Complete Deployment Guide

## Prerequisites
- Azure CLI installed and authenticated (`az login`)
- GitHub account with repository access
- Azure subscription with appropriate permissions
- Bicep CLI (included with Azure CLI)

---

## Phase 0: GitHub Secrets Setup

### Step 0.1: Create Service Principal and GitHub Secret (Execute Once)
The `setup-environment.sh` script automatically creates a GitHub-compatible Service Principal and generates credentials on first use.

First deployment creates `.azure-credentials-<customer>-<env>.json` containing:
- Azure subscription ID
- Service Principal (Client ID, Client Secret)
- Tenant ID

### Step 0.2: Add GitHub Deployment Secret
1. Run `setup-environment.sh` for your first customer/environment (see Phase 1)
2. It generates `.azure-credentials-<customer>-<env>.json`
3. Copy the contents of the credentials file
4. Add as `AZURE_CREDENTIALS` secret in GitHub:
   - `mustrustDataPlatformProcessor` repository → Settings → Secrets → New secret
   - `mustrustDataPlatformAnalyzer` repository → Settings → Secrets → New secret
5. Delete the local credentials file after adding to GitHub:
   ```bash
   rm .azure-credentials-*.json
   ```
   
**Note:** The Service Principal is reused for all customers/environments, so you only need to add the secret once.

---

## Phase 1: Infrastructure Provisioning

### Step 1.1: Update Bicep Parameters
Before running setup-environment.sh, configure `bicep/main.bicepparam`:
- Set `aadTenantId`, `aadClientId`, `aadClientSecret`
- Set `allowedAadGroups` (comma-separated Azure AD group object IDs for PROD access control)
- Configure `location`, `storageAccountSku`, and other parameters as needed

### Step 1.2: Provision Infrastructure
```bash
./setup-environment.sh --customer <name> --environment <env> [--with-analyzer]
```
**Examples:**
```bash
# Provision for YYS Production with Analyzer
./setup-environment.sh --customer yys --environment prod --with-analyzer

# Provision for HCS Development (preprocessor only)
./setup-environment.sh --customer hcs --environment dev
```

**What This Script Does:**
- Creates Azure resource group
- Deploys Bicep template with customer/environment parameters
- Creates/updates storage accounts (web + analyzer)
- Creates App Service for Preprocessor
- (Optional) Creates Cosmos DB and Analyzer Function App
- Sets up initial Azure AD configuration

**Output:** Resource names and deployment details

---

## Phase 2: Application Deployment

### Step 2.1: Deploy Preprocessor + Frontend (GitHub Actions)
1. Go to `mustrustDataPlatformProcessor` repository
2. Navigate to Actions tab → Select deployment workflow
3. Trigger with parameters:
   - `CUSTOMER`: yys
   - `ENVIRONMENT`: prod
4. Workflow will:
   - Build Python environment
   - Deploy code to App Service
   - Upload frontend files to web storage

### Step 2.2: Deploy Analyzer (GitHub Actions)
1. Go to `mustrustDataPlatformAnalyzer` repository
2. Navigate to Actions tab → Select deployment workflow
3. Trigger with parameters:
   - `CUSTOMER`: yys
   - `ENVIRONMENT`: prod
4. Workflow will:
   - Build Node.js environment
   - Deploy code to Function App
   - Set up Event Grid triggers

---

## Phase 3: Configuration & Integration

### Step 3.1: Configure Analyzer AI Settings
```bash
./configure-analyzer-ai.sh --customer yys --environment prod
```
**What This Script Does:**
- Retrieves Document Intelligence and Custom Vision credentials from shared resources
- Configures Azure Language Service integration
- Sets up translator service for document analysis
- Applies custom model IDs and API endpoints to Analyzer Function App settings
- Validates all AI service connections

### Step 3.2: Optional - Enable Easy Auth (Azure AD Authentication)
```bash
./setup-easy-auth.sh --customer yys --environment prod
```
**What This Script Does:**
- Creates Azure AD app registration for Preprocessor
- Configures OAuth 2.0 redirect URIs
- Enables Easy Auth on App Service
- Configures group claims for access control
- Outputs configuration summary

**Manual Steps After Easy Auth Setup:**
1. **Configure Group Claims:**
   - Azure Portal → App registrations → `mustrust-preprocessor-yys-prod` → Token configuration
   - Add groups claim → choose "Security groups"
   
2. **Create Azure AD Group:**
   - Entra ID → Groups → New group
   - Type: Security, Assignment type: Assigned
   - Name: `mustrust-yys-prod-users`
   - Add users to the group
   - Copy the group's Object ID

3. **Update App Settings:**
   - App Service → Configuration → Application settings
   - Set `ALLOWED_AAD_GROUPS` to the group Object ID (comma-separated if multiple)
   - Save and restart the app

4. **Verify:**
   - Sign in to the app
   - Visit `/.auth/me` endpoint
   - Verify `groups` claim contains the group Object ID

---

## Phase 4: Verification & Testing

### Step 4.1: Verify Analyzer Configuration
Compare app settings between environments:
```bash
./verify-analyzer-config.sh --customer yys --env1 dev --env2 prod
```

### Step 4.2: Test Deployment
1. **Preprocessor:**
   - Navigate to App Service URL
   - Login with Azure AD account (if Easy Auth enabled)
   - Test file upload functionality

2. **Analyzer:**
   - Upload a test document to storage account `web-input-files` container
   - Monitor Function App logs
   - Check Cosmos DB for processed data

---

## Maintenance & Cleanup

### Remove Environment
To completely remove a customer/environment deployment:
```bash
./cleanup-environment.sh --customer yys --environment prod
```

**Caution:** This will delete:
- Resource group and all contained resources
- Storage accounts (including uploaded files)
- App Service and Function Apps
- Cosmos DB (if deployed)

---

## Script Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup-environment.sh` | Provision Azure infrastructure | `./setup-environment.sh --customer <name> --environment <env> [--with-analyzer]` |
| `deploy.sh` | Manual Bicep deployment | `./deploy.sh [--subscription SUB_ID]` |
| `configure-analyzer-ai.sh` | Configure AI service credentials | `./configure-analyzer-ai.sh --customer <name> --environment <env>` |
| `setup-easy-auth.sh` | Configure Azure AD authentication | `./setup-easy-auth.sh --customer <name> --environment <env>` |
| `verify-analyzer-config.sh` | Compare settings between environments | `./verify-analyzer-config.sh --customer <name> [--env1 dev] [--env2 prod]` |
| `cleanup-environment.sh` | Delete customer/environment | `./cleanup-environment.sh --customer <name> --environment <env>` |

---

## Troubleshooting

### Azure CLI Not Authenticated
```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### Bicep Validation Error
```bash
az bicep build-params --file bicep/main.bicepparam
```

### Easy Auth Not Working
- Verify Azure AD app registration exists
- Check App Service authentication settings in Azure Portal
- Review Easy Auth logs: App Service → Log stream

---

## Environment Variables

Optional environment variables for scripts:

```bash
# Azure subscription (default: 6a6d110d-80ef-424a-b8bb-24439063ffb2)
export AZURE_SUBSCRIPTION_ID="your-subscription-id"

# Enable verbose output
export VERBOSE=1
```

---

## Quick Reference: Common Deployments

### Deploy New Customer (Full Stack)
```bash
# 1. Provision infrastructure with Analyzer
./setup-environment.sh --customer acme --environment prod --with-analyzer

# 2. Deploy via GitHub Actions (trigger manually in Actions tab)
# → mustrustDataPlatformProcessor workflow
# → mustrustDataPlatformAnalyzer workflow

# 3. Configure AI settings
./configure-analyzer-ai.sh --customer acme --environment prod

# 4. (Optional) Enable Easy Auth
./setup-easy-auth.sh --customer acme --environment prod
```

### Deploy to Existing Environment
```bash
# Only deploy updated code (no infrastructure changes)
# → Trigger GitHub Actions workflows manually
# → Select customer and environment parameters
```

### Verify Environment Health
```bash
./verify-analyzer-config.sh --customer yys --env1 dev --env2 prod
```

### Emergency Cleanup
```bash
./cleanup-environment.sh --customer yys --environment prod
```
