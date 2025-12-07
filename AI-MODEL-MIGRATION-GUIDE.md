# AI Model Migration Guide

## Overview
This guide explains how to migrate AI models from your source environment (HCS) to new customer environments (e.g., YYS).

## Current Situation

### Source Resources (HCS Environment)
- **Document Intelligence**: `surveyformextractor2` in `hcsGroup`
  - ✅ Model 1: `hack-workshop-survey-2025-extractor` (API 2024-11-30, trained successfully)
  - ✅ Model 2: `hcs-survery-extraction-model2` (API 2024-11-30, trained successfully)
  - ✅ Shared across all customers
- **Custom Vision**: `circleMarkerRecognizer` project with NPS circle detection
  - ✅ Shared across all customers

### Target Resources (YYS Dev Environment)  
- **Cosmos DB**: `cosmos-mustrust-yys-dev` (customer-specific)
- **Analyzer Function App**: `func-mustrust-analyzer-yys-dev` (customer-specific)
- **Language Services**: `lang-mustrust-yys-dev` (customer-specific)
- **Document Intelligence**: ✅ Shared from HCS `surveyformextractor2`
- **Custom Vision**: ✅ Shared from HCS `circleMarkerRecognizer`

## Migration Steps

### ✅ DECISION: Shared AI Resources

All AI services (Document Intelligence and Custom Vision) are **shared across customers**:
- Single source of truth for trained models
- Reduced infrastructure complexity and cost
- Simplified model updates (train once, all customers benefit)
- Each customer still gets isolated billing through Cosmos DB and Function Apps
- AI service usage is typically low-volume per customer

**Customer-specific resources remain isolated for:**
- Cosmos DB (data storage)
- Function Apps (compute and execution)
- Language Services (if needed for customer-specific language processing)

---

### 🔧 Function App Configuration

Update the analyzer function app to use the shared AI resources from HCS:

```bash
# Get Document Intelligence and Custom Vision details from HCS resources
# Document Intelligence: surveyformextractor2 in hcsGroup
# Custom Vision: circleMarkerRecognizer → Settings

# Update function app with all AI service configurations
az functionapp config appsettings set \
  --name func-mustrust-analyzer-yys-dev \
  --resource-group rg-mustrust-yys-dev \
  --settings \
    DOCUMENT_INTELLIGENCE_ENDPOINT="https://surveyformextractor2.cognitiveservices.azure.com/" \
    DOCUMENT_INTELLIGENCE_KEY="<from-surveyformextractor2-keys>" \
    WORKSHOP_SURVEY_MODEL_ID="hack-workshop-survey-2025-extractor" \
    HCS_SURVEY_MODEL_ID="hcs-survery-extraction-model2" \
    CUSTOM_VISION_PREDICTION_ENDPOINT="<from-customvision.ai-circleMarkerRecognizer>" \
    CUSTOM_VISION_PREDICTION_KEY="<from-customvision.ai-settings>" \
    CUSTOM_VISION_PROJECT_ID="<from-customvision.ai-settings>" \
    CUSTOM_VISION_ITERATION_NAME="Iteration6"
```

**To get the keys:**
```bash
# Document Intelligence key
az cognitiveservices account keys list \
  --name surveyformextractor2 \
  --resource-group hcsGroup \
  --query key1 -o tsv

# Custom Vision details: Go to https://www.customvision.ai/ → circleMarkerRecognizer → Settings
```

**For YYS Dev Environment:**
- ✅ Document Intelligence: Shared HCS `surveyformextractor2`
- ✅ Models: `hack-workshop-survey-2025-extractor`, `hcs-survery-extraction-model2`
- ✅ Custom Vision: Shared HCS `circleMarkerRecognizer` (Iteration6)

---

## Deployment Workflow for New Customers

### 1. Deploy Infrastructure

```bash
./setup-environment.sh --customer <name> --environment <env> --with-analyzer
```

This creates:
- Resource group
- Storage Account (Bronze layer)
- Function App for preprocessing
- Cosmos DB (Silver/Gold layers)
- Analyzer Function App
- Language Services (customer-specific)

**Does NOT create (uses shared HCS resources):**
- Document Intelligence (shared)
- Custom Vision (shared)

### 2. Configure Function App with Shared AI Resources

Get credentials from HCS resources and configure:

```bash
# Get Document Intelligence key
DOC_INTEL_KEY=$(az cognitiveservices account keys list \
  --name surveyformextractor2 \
  --resource-group hcsGroup \
  --query key1 -o tsv)

# Configure function app
az functionapp config appsettings set \
  --name func-mustrust-analyzer-<customer>-<env> \
  --resource-group rg-mustrust-<customer>-<env> \
  --settings \
    DOCUMENT_INTELLIGENCE_ENDPOINT="https://surveyformextractor2.cognitiveservices.azure.com/" \
    DOCUMENT_INTELLIGENCE_KEY="$DOC_INTEL_KEY" \
    WORKSHOP_SURVEY_MODEL_ID="hack-workshop-survey-2025-extractor" \
    HCS_SURVEY_MODEL_ID="hcs-survery-extraction-model2" \
    CUSTOM_VISION_PREDICTION_ENDPOINT="<from-customvision.ai>" \
    CUSTOM_VISION_PREDICTION_KEY="<from-customvision.ai>" \
    CUSTOM_VISION_PROJECT_ID="<from-customvision.ai>" \
    CUSTOM_VISION_ITERATION_NAME="Iteration6"
```

### 3. Deploy Application Code

Deploy function code to both function apps using GitHub Actions or manual deployment.

### 4. Test End-to-End

Upload test document to `bronze-input-files` container and verify Silver/Gold processing.

---

## Billing Separation Strategy

Each customer gets isolated resources for accurate per-customer billing:

### Customer-Specific (Isolated) Resources:
- ✅ **Function Apps** - Billed per execution and compute time
  - Separate preprocessor and analyzer apps per customer
  - Enables granular cost tracking per customer
  - Main variable cost driver (~$20-50/month per customer)
  
- ✅ **Cosmos DB** - Billed per RU/s consumed
  - Separate database per customer
  - Silver/Gold data isolated
  - Provides accurate per-customer data storage costs (~$25-100/month)
  
- ✅ **Storage Accounts** - Billed per GB stored and operations
  - Bronze layer storage per customer
  - ~$10-30/month depending on volume

- ✅ **Language Services** - Billed per transaction (optional)
  - Separate resource per customer
  - Only if customer-specific language processing needed
  - ~$5-20/month

### Shared (Cost-Optimized) Resources:
- ✅ **Document Intelligence** - Shared across all customers
  - Previously $150-500/month per customer
  - Now ~$150-500/month total for all customers combined
  - Billed per API call for OCR extraction
  - Cost tracked at shared level, not per customer
  - Significant savings for multi-customer deployment

- ✅ **Custom Vision** - Shared across all customers  
  - Training: Only used during model development (one-time cost)
  - Prediction: ~$2 per 1000 transactions
  - NPS circle detection is low-volume (1-2 calls per survey)
  - ~$2/month total for all customers combined
  - No customer data stored (only predictions made)

### Cost Breakdown Example (per customer/month):
- Function Apps: $20-50
- Cosmos DB: $25-100
- Storage: $10-30
- Language Services: $5-20 (if used)
- **Shared AI Services**: Allocated across all customers

**Total per customer**: ~$60-200/month (vs $200-700/month with isolated AI services)
**Savings**: 70-80% reduction in per-customer costs

### Billing Recommendations:
1. **Track shared AI costs separately** - Monitor Document Intelligence and Custom Vision usage at the platform level
2. **Allocate shared costs** - Distribute shared AI costs across customers based on:
   - Equal split (simple)
   - Usage-based (document count, API calls)
   - Customer tier (enterprise vs standard)
3. **Customer-specific billing** - Bill each customer for their isolated resources (Function Apps, Cosmos DB, Storage)
4. **Platform fee** - Add platform/shared infrastructure fee to cover shared AI services

---

## Troubleshooting
- ✅ Custom Vision resource information

Run it with:
---

## Troubleshooting

### Document Intelligence Model Copy Issues

**"ModelNotFound" Error**
- Source model uses an old API version (v2.0)
- Solution: Models trained with API 2024-11-30 can be copied via Studio

**"Conflict - ModelExists" Error**  
- Model ID already exists in target
- Solution: Use a different model ID or delete the existing one first

**Can't See Models in Studio**
- Ensure you've selected the correct resource
- Check that models have "succeeded" status
- Refresh the browser

### Custom Vision Issues

**Project Not Found**
- Verify project ID from Settings in Custom Vision portal
- Ensure you're using the correct endpoint

**Authentication Errors**
- Verify training/prediction keys are correct
- Check that keys haven't been regenerated

### Function App Configuration

**Models Not Working**
- Verify all app settings are configured correctly
- Check that model IDs match exactly
- Ensure endpoints include trailing slash if required
- Review function app logs for detailed errors

## Resources

- Document Intelligence Studio: https://formrecognizer.appliedai.azure.com/studio
- Custom Vision Portal: https://www.customvision.ai/
- Document Intelligence API: https://learn.microsoft.com/azure/ai-services/document-intelligence/
- Custom Vision API: https://learn.microsoft.com/azure/ai-services/custom-vision-service/

