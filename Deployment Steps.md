# MusTrusT Data Platform - Complete Deployment Guide (v0.6)

## Prerequisites
- Azure CLI installed and authenticated (`az login`)
- GitHub account with repository access
- Azure subscription with appropriate permissions
- Bicep CLI (included with Azure CLI)
- Access to Azure AD (Entra ID) for creating security groups (PROD environments)

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

### Step 3.2: Enable Easy Auth (Azure AD Authentication)
```bash
./setup-easy-auth.sh --customer yys --environment prod
```
**What This Script Does:**
- Creates Azure AD app registration for Preprocessor
- **Creates Azure AD security group** `mustrust-{customer}-{environment}-users`
- Configures OAuth 2.0 redirect URIs
- Enables Easy Auth (AuthV2) on App Service
- Sets ALLOWED_AAD_GROUPS app setting with group Object ID
- Outputs configuration summary with group details

**⚠️ CRITICAL - Manual Portal Configuration Required:**
Due to an Azure CLI bug, the script cannot fully configure Easy Auth. You **MUST** complete the following steps in Azure Portal immediately after running the script.

**Step 3.2.1: Fix Easy Auth Identity Provider (REQUIRED)**

After the script completes, the identity provider will be incomplete. Fix it in Azure Portal:

1. **Navigate to App Service:**
   - Azure Portal → Search for: `app-mustrust-preprocessor-{customer}-{env}`
   - Click: **Authentication** (left menu)

2. **Check Identity Provider Status:**
   - If you see "No identity provider" → Click **"Add identity provider"**
   - If Microsoft provider exists → Click **"Edit"** next to it

3. **Configure Identity Provider:**
   - **Identity provider**: Microsoft
   - **App registration type**: Pick an existing app registration in this directory
   - **Name or app ID**: Select `mustrust-preprocessor-{customer}-{env}` (created by script)
   - **Client secret expiration**: 730 days (24 months)
   - **Issuer URL**: Change from `https://sts.windows.net/...` to `https://login.microsoftonline.com/{TENANT_ID}/v2.0`
   - **Allowed token audiences**: Add the Client ID (shown in script output)
   - **Client application requirement**: Allow requests only from this application itself
   - **Identity requirement**: Allow requests from any identity
   - **Tenant requirement**: Allow requests only from the issuer tenant
   - **Restrict access**: Require authentication
   - **Unauthenticated requests**: HTTP 302 Found redirect
   - **Redirect to**: Microsoft
   - **Token store**: Checked ✓
   - Click **"Add"** or **"Save"**

4. **Verify Group Claims (Usually Already Configured):**
   - Azure Portal → **App registrations** → Find `mustrust-preprocessor-{customer}-{env}`
   - Click: **Token configuration** (left menu)
   - If "groups" claim exists → ✓ Skip this step
   - If not → Click **"+ Add groups claim"** → Select **"Security groups"** → **"Add"**

5. **Restart the App Service:**
   ```bash
   az webapp restart \
     --resource-group "rg-mustrust-{customer}-{env}" \
     --name "app-mustrust-preprocessor-{customer}-{env}"
   ```

**Why This Is Required:**
The `az webapp auth update --set` command has a bug where `clientId`, `openIdIssuer`, and `allowedAudiences` don't persist properly in AuthV2. This must be fixed manually in the Portal.

### Step 3.3: Add Users to Security Group
After running setup-easy-auth.sh, add users who should have access:

1. **Get User's Object ID:**
   ```bash
   az ad user show --id "user@domain.com" --query id -o tsv
   ```

2. **Add User to Group:**
   ```bash
   az ad group member add \
     --group "mustrust-yys-prod-users" \
     --member-id "<USER_OBJECT_ID>"
   ```

Repeat for each user who needs access.

### Step 3.4: Test Easy Auth

1. **Navigate to app URL:**
   ```
   https://app-mustrust-preprocessor-{customer}-{env}.azurewebsites.net
   ```

2. **Expected Behavior:**
   - Redirects to Azure AD login
   - After successful login, shows the MusTrusT interface
   - Visit `/.auth/me` endpoint to verify token contains `groups` claim

3. **Troubleshooting:**
   - **"Not found" error**: Easy Auth identity provider not configured → Complete Step 3.2.1
   - **HTTP 401 after login**: User not in security group → Complete Step 3.3
   - **HTTP 502 Bad Gateway**: App needs restart after Easy Auth changes
     ```bash
     az webapp restart --resource-group "rg-mustrust-{customer}-{env}" --name "app-mustrust-preprocessor-{customer}-{env}"
     ```

### Step 3.5: Configure Dictionary for Fuzzy Search (v0.6 New Feature)
After deployment, create initial dictionaries for comment search:

1. **Access Dictionary Management:**
   - Navigate to: `https://app-mustrust-preprocessor-yys-prod.azurewebsites.net/dictionary-management.html`

2. **Create Bank Survey Dictionary:**
   - Survey Type: `bank`
   - Add keywords with aliases:
     ```
     トイレ → toilet, 便所, 和式トイレ, 洋式トイレ
     清掃 → 掃除, クリーニング, cleaning
     対応 → サービス, 接客, service
     待ち時間 → 待機, waiting, queue
     ```

3. **Create Hygiene Survey Dictionary:**
   - Survey Type: `hygiene`
   - Add keywords with aliases:
     ```
     清潔 → きれい, クリーン, clean
     衛生 → 衛生的, sanitary, hygiene
     確認 → チェック, check, inspection
     ```

4. **Create Workshop Survey Dictionary:**
   - Survey Type: `workshop`
   - Add keywords with aliases:
     ```
     理解 → わかりやすい, understand, comprehension
     内容 → コンテンツ, content, material
     講師 → 先生, instructor, teacher
     ```

5. **Test Fuzzy Search:**
   - Go to analytics pages (bank/hygiene/workshop)
   - Use search box with keywords or typos
   - Verify Levenshtein distance matching works (e.g., "トイイレ" matches "トイレ")

---

## Phase 4: Verification & Testing

### Step 4.1: Verify Analyzer Configuration
Compare app settings between environments:
```bash
./verify-analyzer-config.sh --customer yys --env1 dev --env2 prod
```

### Step 4.2: Verify v0.6 Features

**1. Workshop Sentiment Analysis (3 Text Fields):**
- Upload a workshop survey form with Q1.7, Q2, Q3 text responses
- Check analytics: `https://app-mustrust-preprocessor-yys-prod.azurewebsites.net/workshop-analytics.html`
- Verify each text field shows:
  - Sentiment (positive/negative/neutral)
  - Confidence score
  - Language detection
  - Translation (if non-Japanese)

**2. Fuzzy Search with Dictionary:**
- Navigate to bank/hygiene/workshop analytics
- Try searching with typos (e.g., "トイイレ" should find "トイレ")
- Try dictionary aliases (e.g., "toilet" should find "トイレ")
- Verify search info shows: "X / Y 件が一致"

**3. Storage Consolidation:**
- Verify only 2 storage accounts exist:
  ```bash
  az storage account list \
    --resource-group "rg-mustrust-yys-prod" \
    --query "[].name" -o table
  ```
  - Expected: `stmustrustwebyys<hash>` + `stmustrustanalyzeryys<hash>`

### Step 4.3: Test Deployment
1. **Preprocessor:**
   - Navigate to App Service URL
   - Login with Azure AD account (verify user is in security group)
   - Test file upload functionality
   - Check fuzzy search on analytics pages

2. **Analyzer:**
   - Upload a test document to storage account `web-input-files` container
   - Monitor Function App logs
   - Check Cosmos DB Gold layer for enriched data with sentiment analysis

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

### Deploy New Customer (Full Stack) - v0.6
```bash
# 1. Provision infrastructure with Analyzer
./setup-environment.sh --customer acme --environment prod --with-analyzer

# 2. Configure AI settings
./configure-analyzer-ai.sh --customer acme --environment prod

# 3. Enable Easy Auth (creates app registration + security group)
./setup-easy-auth.sh --customer acme --environment prod

# 4. Add users to security group
az ad user show --id "user@domain.com" --query id -o tsv
az ad group member add \
  --group "mustrust-acme-prod-users" \
  --member-id "<USER_OBJECT_ID>"

# 5. Deploy via GitHub Actions (trigger manually in Actions tab)
# → mustrustDataPlatformProcessor workflow (tag: mustrust-data-v0.6)
# → mustrustDataPlatformAnalyzer workflow (tag: mustrust-data-v0.6)

# 6. Create dictionaries for fuzzy search
# Access: https://app-mustrust-preprocessor-acme-prod.azurewebsites.net/dictionary-management.html
# Create dictionaries for: bank, hygiene, workshop

# 7. Verify deployment
./verify-analyzer-config.sh --customer acme --env1 dev --env2 prod
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
