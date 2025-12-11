# Complete Deployment Steps

This guide provides the exact steps to deploy the MusTrust Data Platform from scratch.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Access to Azure subscription: `6a6d110d-80ef-424a-b8bb-24439063ffb2`
- Access to shared AI resources in `hcsGroup`, `hygieneMasterGroup`, and `CustomSymbolRecognizerGroup`
- Repository cloned locally

## Shared AI Resources (One-time Setup)

These resources are shared across all customers and environments. They should already exist:

| Resource | Resource Group | Purpose |
|----------|---------------|---------|
| `surveyformextractor2` | `hcsGroup` | Document Intelligence for custom models |
| `hygieneMasterClassifer` | `hygieneMasterGroup` | Document classification |
| `customSymbolRecognizer-Prediction` | `CustomSymbolRecognizerGroup` | Custom Vision for symbol recognition |

## Required Information

Before deployment, gather these values:

### AI Service Credentials (Shared)
- **Custom Vision Project ID**: `3b991de4-fcd4-415a-b24a-7e42c6eb53dd`
- **Bank Custom Vision Prediction Key**: `d3b436df50794eb5a39bfcad78b89ca1`
- **Bank Custom Model ID**: `hcs-survery-extraction-model2`
- **Bank Survey Model ID**: `hack-workshop-survey-2025-extractor`

### Service Principal (Per Customer)
- Client ID: `153914e2-212b-4f2d-915e-38ea7de4b8ef` (yys-dev-v2)
- Subscription-scoped with Contributor role

---

## Deployment Steps

### Step 1: Deploy Infrastructure

Deploy Bronze layer only (without Analyzer):

```bash
./setup-environment.sh --customer <customer> --environment <env>
```

Or deploy complete stack (Bronze + Silver + Gold):

```bash
./setup-environment.sh --customer <customer> --environment <env> --with-analyzer
```

**Examples:**
```bash
# Development environment
./setup-environment.sh --customer yys --environment dev --with-analyzer

# Production environment
./setup-environment.sh --customer yys --environment prod --with-analyzer
```

**What this does:**
- Creates resource group: `rg-mustrust-<customer>-<env>`
- Deploys storage account with containers (bronze-input-files, bronze-processed-files)
- Deploys Bronze preprocessor function app (Python, Linux Flex Consumption)
- If `--with-analyzer`: Deploys Cosmos DB, Language Service, and Analyzer function app (Node.js, Windows Consumption)
- Configures Application Insights for monitoring
- Outputs deployment details to `deployment-output.json`

**Troubleshooting:**
- If deployment fails, check `deployment-output.json` for error details
- If you see "FlagMustBeSetForRestore" error, purge soft-deleted resources:
  ```bash
  az cognitiveservices account list-deleted --subscription <subscription-id>
  az cognitiveservices account purge --name <resource-name> --resource-group <rg-name> --location japaneast
  ```

---

### Step 2: Configure AI Credentials (Analyzer Only)

If you deployed with `--with-analyzer`, configure shared AI service credentials:

```bash
./configure-analyzer-ai.sh --customer <customer> --environment <env>
```

**Example:**
```bash
./configure-analyzer-ai.sh --customer yys --environment dev
```

**You will be prompted for:**
1. Custom Vision Project ID: `3b991de4-fcd4-415a-b24a-7e42c6eb53dd`
2. Bank Custom Vision Prediction Key: `d3b436df50794eb5a39bfcad78b89ca1`
3. Bank Custom Model ID: `hcs-survery-extraction-model2`
4. Bank Survey Model ID: `hack-workshop-survey-2025-extractor`

**What this does:**
- Retrieves credentials from shared AI resources (Document Intelligence, Classifier, Custom Vision)
- Configures 23+ environment variables in the Analyzer function app
- Sets up connections to Cosmos DB, Language Service, and AI services

---

### Step 3: Verify Configuration

Check that all settings are configured correctly:

```bash
./verify-analyzer-config.sh --customer <customer>
```

**Example:**
```bash
./verify-analyzer-config.sh --customer yys
```

**Expected output:**
- ✅ All 23 required settings configured
- ℹ️ Additional settings listed (build configs, Application Insights, etc.)
- Environment-specific settings (LANGUAGE_SERVICE_ENDPOINT, COSMOS_DB_CONNECTION_STRING) shown as expected differences

**If any settings are missing:**
```bash
./configure-analyzer-ai.sh --customer <customer> --environment <env>
```

---

### Step 4: Deploy Application Code

#### Bronze Preprocessor (Python)

Repository: `mustrustDataPlatformPreProcessor`

1. Ensure GitHub Actions workflow is configured with secrets:
   - `AZURE_CLIENT_ID`: `153914e2-212b-4f2d-915e-38ea7de4b8ef`
   - `AZURE_TENANT_ID`: Your tenant ID
   - `AZURE_SUBSCRIPTION_ID`: `6a6d110d-80ef-424a-b8bb-24439063ffb2`

2. Push to branch:
   - `develop` → deploys to dev
   - `main` → deploys to prod

**Verify deployment:**
```bash
az functionapp function list \
  --name func-mustrust-preprocessor-<customer>-<env> \
  --resource-group rg-mustrust-<customer>-<env>
```

#### Analyzer (Node.js) - If deployed

Repository: `mustrustDataPlatformAnalyzer`

1. Ensure GitHub Actions workflow is configured with same secrets
2. Push to branch:
   - `develop` → deploys to dev
   - `main` → deploys to prod

**Verify deployment:**
```bash
az functionapp function list \
  --name func-mustrust-analyzer-<customer>-<env> \
  --resource-group rg-mustrust-<customer>-<env>
```

---

### Step 5: Test End-to-End Pipeline

#### Test Bronze Layer

1. Upload a test file to storage:
   ```bash
   az storage blob upload \
     --account-name stmustrust<customer><env> \
     --container-name bronze-input-files \
     --name test-document.pdf \
     --file /path/to/test-document.pdf \
     --auth-mode login
   ```

2. Check function logs:
   ```bash
   az functionapp logs tail \
     --name func-mustrust-preprocessor-<customer>-<env> \
     --resource-group rg-mustrust-<customer>-<env>
   ```

3. Verify processed file appears in:
   - Container: `bronze-processed-files`
   - Queue: `bronze-file-processing-queue` (message sent)

#### Test Silver Layer (If Analyzer deployed)

1. Check Cosmos DB for extracted data:
   ```bash
   az cosmosdb sql container query \
     --account-name cosmos-mustrust-<customer>-<env> \
     --database-name mustrustDataPlatform \
     --container-name silver-extracted-documents \
     --query-text "SELECT * FROM c ORDER BY c._ts DESC OFFSET 0 LIMIT 10"
   ```

2. Verify document contains:
   - Classification results
   - Extracted form fields
   - Symbol recognition results

#### Test Gold Layer (If Analyzer deployed)

1. Check Cosmos DB for enriched data:
   ```bash
   az cosmosdb sql container query \
     --account-name cosmos-mustrust-<customer>-<env> \
     --database-name mustrustDataPlatform \
     --container-name gold-enriched-documents \
     --query-text "SELECT * FROM c ORDER BY c._ts DESC OFFSET 0 LIMIT 10"
   ```

2. Verify document contains:
   - Translations
   - Sentiment analysis
   - Key phrase extraction
   - Entity recognition

---

## Quick Reference

### Common Commands

```bash
# Deploy new environment
./setup-environment.sh --customer yys --environment dev --with-analyzer

# Configure AI credentials
./configure-analyzer-ai.sh --customer yys --environment dev

# Verify configuration
./verify-analyzer-config.sh --customer yys

# Check deployment status
az deployment sub show --name mustrust-yys-dev --query properties.provisioningState

# List all resources in environment
az resource list --resource-group rg-mustrust-yys-dev --output table

# Check function app status
az functionapp show \
  --name func-mustrust-analyzer-yys-dev \
  --resource-group rg-mustrust-yys-dev \
  --query state

# View function app logs
az functionapp logs tail \
  --name func-mustrust-analyzer-yys-dev \
  --resource-group rg-mustrust-yys-dev
```

### Cleanup

To remove an entire environment:

```bash
./cleanup-environment.sh --customer <customer> --environment <env>
```

**Warning:** This deletes ALL resources. Some resources (Cosmos DB, Cognitive Services) are soft-deleted and can be recovered within 90 days.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Bronze Layer                            │
│  Storage → Preprocessor Function (Python) → Queue              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Silver Layer                            │
│  Queue → Analyzer Function (Node.js)                           │
│  ├─ Document Intelligence (Custom Models)                      │
│  ├─ Classifier (Document Type)                                 │
│  └─ Custom Vision (Symbol Recognition)                         │
│  → Cosmos DB (silver-extracted-documents)                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Gold Layer                              │
│  Cosmos Change Feed → Analyzer Function (Node.js)              │
│  └─ Language Service (Translation, Sentiment, Entities)        │
│  → Cosmos DB (gold-enriched-documents)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Current Deployments

### YYS Customer

| Environment | Status | Bronze | Analyzer | AI Configured |
|-------------|--------|--------|----------|---------------|
| dev | ✅ Deployed | ✅ | ✅ | ✅ |
| prod | ✅ Deployed | ✅ | ✅ | ✅ |

### Resource Naming Convention

| Resource Type | Naming Pattern | Example |
|--------------|----------------|---------|
| Resource Group | `rg-mustrust-<customer>-<env>` | `rg-mustrust-yys-dev` |
| Storage Account | `stmustrust<customer><env>` | `stmustrustyysdev` |
| Preprocessor Function | `func-mustrust-preprocessor-<customer>-<env>` | `func-mustrust-preprocessor-yys-dev` |
| Analyzer Function | `func-mustrust-analyzer-<customer>-<env>` | `func-mustrust-analyzer-yys-dev` |
| Cosmos DB | `cosmos-mustrust-<customer>-<env>` | `cosmos-mustrust-yys-dev` |
| Language Service | `lang-mustrust-<customer>-<env>` | `lang-mustrust-yys-dev` |

---

## Troubleshooting

### Deployment Fails

1. Check `deployment-output.json` for detailed error messages
2. Look for soft-deleted resources:
   ```bash
   az cognitiveservices account list-deleted
   ```
3. Purge if needed:
   ```bash
   az cognitiveservices account purge --name <name> --resource-group <rg> --location japaneast
   ```

### Function App Not Running

1. Check app settings:
   ```bash
   az functionapp config appsettings list \
     --name <function-app-name> \
     --resource-group <resource-group>
   ```

2. Check application logs:
   ```bash
   az functionapp logs tail --name <function-app-name> --resource-group <resource-group>
   ```

3. Restart function app:
   ```bash
   az functionapp restart --name <function-app-name> --resource-group <resource-group>
   ```

### AI Credentials Not Working

1. Verify configuration:
   ```bash
   ./verify-analyzer-config.sh --customer <customer>
   ```

2. Reconfigure if needed:
   ```bash
   ./configure-analyzer-ai.sh --customer <customer> --environment <env>
   ```

3. Test AI service access:
   ```bash
   # Test Document Intelligence
   az cognitiveservices account show \
     --name surveyformextractor2 \
     --resource-group hcsGroup
   
   # Test Classifier
   az cognitiveservices account show \
     --name hygieneMasterClassifer \
     --resource-group hygieneMasterGroup
   ```

---

## Next Steps After Deployment

1. **Monitor Application Insights**
   - Check for errors and performance metrics
   - Set up alerts for failures

2. **Configure GitHub Actions**
   - Set up CI/CD for automated deployments
   - Configure branch protection rules

3. **Test with Real Data**
   - Upload sample documents
   - Verify extraction accuracy
   - Validate enrichment results

4. **Set Up Additional Environments**
   - Repeat steps for other customers or environments
   - Use same shared AI resources

5. **Documentation**
   - Document any custom model IDs
   - Update AI credentials if resources change
   - Keep track of Custom Vision iteration names

---

## Support

- Infrastructure Repository: `mustrustDataPlatformAutomation`
- Preprocessor Code: `mustrustDataPlatformPreProcessor`
- Analyzer Code: `mustrustDataPlatformAnalyzer`
- Azure Subscription: `6a6d110d-80ef-424a-b8bb-24439063ffb2`
