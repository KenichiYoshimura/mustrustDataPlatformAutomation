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

## Phase 2: Configuration & Integration

### Step 2.1: Configure Analyzer AI Settings
```bash
./configure-analyzer-ai.sh --customer yys --environment prod
```
**What This Script Does:**
- Retrieves Document Intelligence and Custom Vision credentials from shared resources
- Configures Azure Language Service integration
- Sets up translator service for document analysis
- Applies custom model IDs and API endpoints to Analyzer Function App settings
- Validates all AI service connections

### Step 2.2: Enable Easy Auth (Azure AD Authentication)
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

**Step 2.2.1: Fix Easy Auth Identity Provider (REQUIRED)**

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

**Step 2.2.2: Verify Group Membership Claims in Manifest (CRITICAL)**

The Token Configuration alone is not sufficient. You **MUST** verify the app manifest has the correct setting:

1. **Navigate to App Manifest:**
   - Azure Portal → **App registrations** → Find `mustrust-preprocessor-{customer}-{env}`
   - Click: **Manifest** (left menu)

2. **Search for groupMembershipClaims:**
   - Press Ctrl+F (or Cmd+F on Mac)
   - Search for: `groupMembershipClaims`
   - Find the line: `"groupMembershipClaims": null,` or `"groupMembershipClaims": "SecurityGroup",`

3. **Fix if Null:**
   - If the value is `null`, change it to `"SecurityGroup"`
   - Example: `"groupMembershipClaims": "SecurityGroup",`
   - Click **Save** at the top

4. **Why This Is Critical:**
   - Without this setting, Azure AD will **NOT** include groups in the authentication token
   - Users will get "not in permitted group" errors even if they are in the security group
   - Token Configuration alone doesn't work without this manifest setting

5. **Restart the App Service:**
   ```bash
   az webapp restart \
     --resource-group "rg-mustrust-{customer}-{env}" \
     --name "app-mustrust-preprocessor-{customer}-{env}"
   ```

**Why This Is Required:**
The `az webapp auth update --set` command has a bug where `clientId`, `openIdIssuer`, and `allowedAudiences` don't persist properly in AuthV2. This must be fixed manually in the Portal.

### Step 2.3: Add Users to Security Group
After running setup-easy-auth.sh, add users who should have access.

**Option A: Using Azure Portal (Recommended for non-technical users)**

1. **Navigate to Azure AD Groups:**
   - Azure Portal → Search for: **"Azure Active Directory"** or **"Microsoft Entra ID"**
   - Click: **Groups** (left menu)

2. **Find the Security Group:**
   - Search for: `mustrust-{customer}-{environment}-users`
   - Example: `mustrust-hcs-prod-users`
   - Click on the group name

3. **Add Members:**
   - Click: **Members** (left menu)
   - Click: **+ Add members** (top button)
   - Search for users by name or email
   - Select users from the list
   - Click: **Select** button

4. **Verify:**
   - The user should now appear in the Members list
   - User can now access the application after login

**Option B: Using Azure CLI**

1. **Get User's Object ID:**
   ```bash
   az ad user show --id "user@domain.com" --query id -o tsv
   ```

2. **Add User to Group:**
   ```bash
   az ad group member add \
     --group "mustrust-{customer}-{environment}-users" \
     --member-id "<USER_OBJECT_ID>"
   ```
   Example:
   ```bash
   az ad group member add \
     --group "mustrust-hcs-prod-users" \
     --member-id "0c7e6d49-b839-4bf8-9e02-e80d66ca091f"
   ```

3. **Verify Membership:**
   ```bash
   az ad group member list \
     --group "mustrust-{customer}-{environment}-users" \
     --query "[].{Name:displayName, Email:userPrincipalName}" -o table
   ```

Repeat for each user who needs access.

### Step 2.4: Test Easy Auth

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

---

## Phase 3: Application Deployment

### Step 3.1: Deploy Preprocessor + Frontend (GitHub Actions)
1. Go to `mustrustDataPlatformProcessor` repository
2. Navigate to Actions tab → Select deployment workflow
3. Trigger with parameters:
   - `CUSTOMER`: yys, hcs, etc.
   - `ENVIRONMENT`: prod
4. Workflow will:
   - Build Python environment
   - Deploy code to App Service
   - Upload frontend files to web storage

### Step 3.2: Deploy Analyzer (GitHub Actions)
1. Go to `mustrustDataPlatformAnalyzer` repository
2. Navigate to Actions tab → Select deployment workflow
3. Trigger with parameters:
   - `CUSTOMER`: yys, hcs, etc.
   - `ENVIRONMENT`: prod
4. Workflow will:
   - Build Node.js environment
   - Deploy code to Function App
   - Set up Event Grid triggers

### Step 3.3: Configure Custom Domain (Optional)
If you want to use a custom domain instead of the default Azure hostname:

**Step 3.3.1: Get Domain Verification Information**

```bash
# Get the default hostname
az webapp show \
  --name "app-mustrust-preprocessor-{customer}-{env}" \
  --resource-group "rg-mustrust-{customer}-{env}" \
  --query "defaultHostName" -o tsv

# Get the verification ID
az webapp show \
  --name "app-mustrust-preprocessor-{customer}-{env}" \
  --resource-group "rg-mustrust-{customer}-{env}" \
  --query "customDomainVerificationId" -o tsv
```

Example output:
- Default hostname: `app-mustrust-preprocessor-hcs-prod.azurewebsites.net`
- Verification ID: `C870C7607F8C73DF1B1FCE1398258A7D8D1862D5256404510A12514028F87636`

**Step 3.3.2: Configure DNS Records**

In your DNS provider (Cloudflare, Route53, etc.), add these records:

1. **CNAME Record:**
   - Type: `CNAME`
   - Name: `hcs` (or your subdomain)
   - Target: `app-mustrust-preprocessor-hcs-prod.azurewebsites.net`
   - Proxy status: **DNS only** (if using Cloudflare)

2. **TXT Record (for verification):**
   - Type: `TXT`
   - Name: `asuid.hcs` (asuid + your subdomain)
   - Content: `<verification-id-from-step-1>`
   - TTL: Auto

Wait 1-5 minutes for DNS propagation.

**Step 3.3.3: Add Custom Domain in Azure Portal**

1. **Navigate to Custom Domains:**
   - Azure Portal → Search for: `app-mustrust-preprocessor-{customer}-{env}`
   - Left menu → Click: **Custom domains**

2. **Add Custom Domain:**
   - Click: **+ Add custom domain**
   - Domain provider: "All other domain services"
   - TLS/SSL certificate: "App Service Managed Certificate"
   - Custom domain: Enter your domain (e.g., `hcs.yysolutions.jp`)
   - Click: **Validate**
   - If validation passes (green checkmarks), click: **Add**

**Step 3.3.4: Enable HTTPS (SSL Certificate)**

1. Find your custom domain in the list
2. Click the **⋮** (three dots) next to it
3. Select: **Add binding**
4. TLS/SSL type: **SNI SSL**
5. Certificate: **Create App Service Managed Certificate**
6. Click: **Add binding**
7. Wait 2-5 minutes for certificate provisioning

**Step 3.3.5: Update Azure AD Redirect URI**

Add the custom domain to the app registration:

```bash
az ad app update \
  --id <client-id-from-setup-easy-auth> \
  --web-redirect-uris \
    "https://app-mustrust-preprocessor-{customer}-{env}.azurewebsites.net/.auth/login/aad/callback" \
    "https://{your-custom-domain}/.auth/login/aad/callback"
```

Example:
```bash
az ad app update \
  --id bd09b40b-a298-4bda-ac24-a6d70b8f35db \
  --web-redirect-uris \
    "https://app-mustrust-preprocessor-hcs-prod.azurewebsites.net/.auth/login/aad/callback" \
    "https://hcs.yysolutions.jp/.auth/login/aad/callback"
```

**Step 3.3.6: Configure Allowed Token Audiences (CRITICAL)**

⚠️ **Without this step, users will get login loops when accessing via custom domain!**

1. **Navigate to Easy Auth:**
   - Azure Portal → `app-mustrust-preprocessor-{customer}-{env}`
   - Click: **Authentication** (left menu)

2. **Edit Microsoft Identity Provider:**
   - Click **Edit** next to the Microsoft provider

3. **Add Allowed Token Audiences:**
   - Scroll to: **Allowed token audiences**
   - You should see the Client ID already listed
   - Click **+ Add** and enter: `https://{your-custom-domain}`
   - Click **+ Add** and enter: `https://app-mustrust-preprocessor-{customer}-{env}.azurewebsites.net`
   - Click **Save**

   Example for HCS production:
   - `bd09b40b-a298-4bda-ac24-a6d70b8f35db` (Client ID)
   - `https://hcs.yysolutions.jp`
   - `https://app-mustrust-preprocessor-hcs-prod.azurewebsites.net`

4. **Restart the App Service:**
   ```bash
   az webapp restart \
     --resource-group "rg-mustrust-{customer}-{env}" \
     --name "app-mustrust-preprocessor-{customer}-{env}"
   ```

5. **Test:**
   - Clear browser cache completely
   - Navigate to: `https://{your-custom-domain}`
   - Should login successfully without loops

**Why This Is Required:**
Easy Auth validates the token audience (the URL being accessed). Without adding the custom domain to allowed audiences, the token validation fails and causes login loops.

**Step 3.3.7: Update Frontend Custom Domain Mapping (CODE CHANGE REQUIRED)**

⚠️ **The frontend needs to know about custom domains to call the correct API!**

1. **Edit the navigation.js file:**
   - File: `mustrustDataPlatformProcessor/frontend/js/navigation.js`
   - Find the `customDomainMap` object (around line 12)

2. **Add your custom domain mapping:**
   ```javascript
   const customDomainMap = {
       'hcs.yysolutions.jp': { customer: 'hcs', environment: 'prod' },
       '{your-domain}': { customer: '{customer}', environment: '{env}' }
   };
   ```

3. **Commit and deploy:**
   ```bash
   cd mustrustDataPlatformProcessor
   git add frontend/js/navigation.js
   git commit -m "Add custom domain mapping for {customer}-{env}"
   git push origin develop  # or main for production
   ```

4. **Trigger GitHub Actions deployment:**
   - Go to: GitHub → mustrustDataPlatformProcessor → Actions
   - Run: "Deploy Preprocessor to App Service" workflow
   - Select: customer={customer}, environment={env}

**Why This Is Required:**
The frontend auto-detects the customer/environment from the hostname. Custom domains don't match the standard patterns (app-mustrust-preprocessor-{customer}-{env}.azurewebsites.net), so they need explicit mapping. Without this, the frontend will use the wrong API backend.

Now you can access the app via `https://{your-custom-domain}`

### Step 3.4: Configure Dictionary for Fuzzy Search (v0.6 New Feature)
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

# 4. REQUIRED: Fix Easy Auth in Azure Portal (Step 2.2.1)
# - Navigate to App Service → Authentication
# - Edit/Add Microsoft identity provider
# - Fix Issuer URL and add Client ID to allowed audiences
# - Restart app service

# 5. Add users to security group
az ad user show --id "user@domain.com" --query id -o tsv
az ad group member add \
  --group "mustrust-acme-prod-users" \
  --member-id "<USER_OBJECT_ID>"

# 6. Deploy via GitHub Actions (trigger manually in Actions tab)
# → mustrustDataPlatformProcessor workflow (customer=acme, environment=prod)
# → mustrustDataPlatformAnalyzer workflow (customer=acme, environment=prod)

# 7. Create dictionaries for fuzzy search
# Access: https://app-mustrust-preprocessor-acme-prod.azurewebsites.net/dictionary-management.html
# Create dictionaries for: bank, hygiene, workshop

# 8. Verify deployment
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
