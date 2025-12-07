# Azure Infrastructure Requirements - Silver & Gold Layers

## Project Overview
This document defines the Azure infrastructure requirements for deploying the **Silver (Extraction)** and **Gold (Enrichment)** layers of the medallion architecture for the mustrust Data Platform Analyzer.

**Architecture Pattern**: Bronze → Silver → Gold → Reports
- **Bronze**: Raw document storage (already deployed)
- **Silver**: OCR extraction and document parsing
- **Gold**: AI enrichment (sentiment, translation, insights)
- **Reports**: HTTP-triggered report generation APIs

## Current System Architecture

### Document Processing Pipeline
```
Bronze (Blob Storage)
  ↓ Queue Trigger
Silver Extraction Processor (Azure Function)
  → Cosmos DB (silver-extracted-documents)
  ↓ Change Feed Trigger
Gold Enrichment Processor (Azure Function)
  → Cosmos DB (gold-enriched-documents)
  ↓ HTTP Trigger
Report APIs (Azure Function)
  → HTML/JSON outputs
```

### Supported Document Types
1. **Bank Survey** (`bank-survey`) - Custom trained model
2. **Workshop Survey** (`workshop-survey`) - Custom trained model
3. **Hygiene Form** (`hygiene-form`) - Important Management Implementation Record (実施記録：重要管理)
4. **General Form** (`general-form`) - Prebuilt layout model (catch-all)

**Plugin-based framework**: Easy to add new extractors without infrastructure changes.

## Silver Layer Infrastructure Requirements

### 1. Azure Function App (Silver & Gold Processing)
```bicep
// Runtime Configuration
// NOTE: Silver and Gold processors share the same Function App
- Runtime: Node.js 18+ (LTS)
- OS: Linux
- App Service Plan: Consumption or Premium (EP1 recommended for production)
- Always On: true (if using Premium plan)
```

**Functions (Silver Layer)**:
- `SilverExtractionProcessor` - Queue-triggered (processes Bronze → Silver)
- `CategoryBrowsingAPI` - HTTP-triggered (browse extracted documents)

**Functions (Gold Layer)**:
- `GoldEnrichmentProcessor` - Change Feed triggered (processes Silver → Gold)
- `GoldCategoryBrowsingAPI` - HTTP-triggered (browse enriched documents)

**Functions (Reports Layer)** - Optional: can share or deploy separately
- `BankSurveyReportAPI` - HTTP-triggered report generation
- `WorkshopSurveyReportAPI` - HTTP-triggered report generation
- `HygieneFormReportAPI` - HTTP-triggered report generation
- `GeneralFormReportAPI` - HTTP-triggered report generation

**Required App Settings** (Silver + Gold + Reports):
```
AzureWebJobsStorage = "<storage-connection-string>"
FUNCTIONS_WORKER_RUNTIME = "node"
FUNCTIONS_EXTENSION_VERSION = "~4"

// Cosmos DB (All Layers)
COSMOS_DB_CONNECTION_STRING = "<cosmos-connection-string>"
COSMOS_DB_DATABASE_NAME = "mustrustDataPlatform"
COSMOS_DB_SILVER_CONTAINER = "silver-extracted-documents"
COSMOS_DB_GOLD_CONTAINER = "gold-enriched-documents"
COSMOS_DB_LEASES_CONTAINER = "leases"

// Azure Document Intelligence (Form Recognizer) - Silver Layer
DOCUMENT_INTELLIGENCE_ENDPOINT = "<form-recognizer-endpoint>"
DOCUMENT_INTELLIGENCE_KEY = "<form-recognizer-key>"

// Custom Models (Document Intelligence) - Silver Layer
BANK_SURVEY_MODEL_ID = "<custom-model-id-for-bank-survey>"
WORKSHOP_SURVEY_MODEL_ID = "<custom-model-id-for-workshop-survey>"

// Azure Custom Vision (Circle Detection for NPS) - Silver Layer
CUSTOM_VISION_PREDICTION_ENDPOINT = "<custom-vision-endpoint>"
CUSTOM_VISION_PREDICTION_KEY = "<custom-vision-key>"
CUSTOM_VISION_PROJECT_ID = "<project-id>"
CUSTOM_VISION_ITERATION_NAME = "Iteration1"

// Azure Language Services (Sentiment + Translation) - Gold Layer
LANGUAGE_SERVICE_ENDPOINT = "<language-service-endpoint>"
LANGUAGE_SERVICE_KEY = "<language-service-key>"
TRANSLATION_TARGET_LANGUAGE = "en"

// Bronze Layer (Input) - Silver Layer
BRONZE_STORAGE_CONNECTION_STRING = "<bronze-storage-connection-string>"
BRONZE_QUEUE_NAME = "bronze-document-queue"
```

### 2. Cosmos DB Container (Silver)
```bicep
// Container: silver-extracted-documents
- Database: mustrustDataPlatform
- Partition Key: /documentType
- Throughput: Autoscale (min 400 RU/s, max 4000 RU/s recommended)
- Indexing Policy: Default (index all properties)
- TTL: Disabled (keep all extracted documents)
```

**Document Schema**:
```json
{
  "id": "unique-document-id",
  "documentType": "bank-survey | workshop-survey | hygiene-form | general-form",
  "extractedData": { /* category-specific structured data */ },
  "metadata": {
    "fileName": "survey.pdf",
    "folderPath": "/company-name/2024-12",
    "companyName": "Acme Corp",
    "pageNumber": 1,
    "executionId": "guid",
    "extractedAt": "2024-12-07T10:00:00Z",
    "modelType": "custom | prebuilt-layout",
    "modelId": "bank-survey-model-v1"
  },
  "bronzeMetadata": { /* original Bronze metadata */ }
}
```

**Indexing Requirements**:
- `/documentType` (partition key)
- `/metadata/companyName`
- `/metadata/extractedAt`
- `/metadata/fileName`

### 3. Azure Document Intelligence (Form Recognizer) - SHARED RESOURCE
```bicep
// Cognitive Service - SHARED ACROSS ALL CUSTOMER ENVIRONMENTS
// Resource: surveyformextractor2 (in hcsGroup resource group)
// NOT created per customer - shared to reduce costs
- SKU: S0 (Standard)
- Kind: FormRecognizer
- Custom Model Training: Already trained and shared
```

**Shared Custom Models** (already trained):
1. **hack-workshop-survey-2025-extractor** - Extract workshop survey fields
2. **hcs-survery-extraction-model2** - Extract survey fields

**Prebuilt Models Used**:
- `prebuilt-layout` - For general forms (tables, text, structure)

**Configuration**:
- Endpoint and keys are configured in Function App settings during deployment
- Models are NOT copied per customer - all customers use the same trained models
- Billing is tracked at the shared resource level

### 4. Azure Custom Vision (Circle Detection) - SHARED RESOURCE
```bicep
// Cognitive Service - SHARED ACROSS ALL CUSTOMER ENVIRONMENTS
// Resource: circleMarkerRecognizer (in hcsGroup resource group)
// NOT created per customer - shared to reduce costs
- SKU: S0 (Standard)
- Project Type: Object Detection
- Domain: General (compact) - for edge deployment
```

**Shared Trained Model**: 
- Project: circleMarkerRecognizer
- Purpose: Detect filled/unfilled circles for NPS scoring (0-10 scale)
- Latest Iteration: Iteration6 (published)

**Configuration**:
- Prediction endpoint and keys are configured in Function App settings during deployment
- Model is NOT trained per customer - all customers use the same trained model
- Billing is tracked at the shared resource level

### 5. Azure Storage Queue
```bicep
// Queue: bronze-document-queue (already exists in Bronze layer)
// Silver Function App reads from this queue
```

---

## Gold Layer Infrastructure Requirements

**Note**: Gold layer functions are deployed in the same Function App as Silver layer (see above).

### 1. Cosmos DB Containers (Gold)
```bicep
// Container 1: gold-enriched-documents
- Database: mustrustDataPlatform
- Partition Key: /documentType
- Throughput: Autoscale (min 400 RU/s, max 4000 RU/s recommended)
- Indexing Policy: Custom (see below)
- TTL: Disabled

// Container 2: leases (Change Feed tracking)
- Database: mustrustDataPlatform
- Partition Key: /id
- Throughput: 400 RU/s (manual)
- TTL: Disabled
```

**Document Schema (gold-enriched-documents)**:
```json
{
  "id": "same-as-silver-document-id",
  "documentType": "bank-survey | workshop-survey | hygiene-form | general-form",
  "extractedData": { /* from Silver layer */ },
  "enrichment": {
    "sentimentAnalysis": {
      "overall": "positive | neutral | negative",
      "confidenceScores": { "positive": 0.85, "neutral": 0.10, "negative": 0.05 },
      "detectedLanguage": "ja",
      "fieldSentiments": [ /* per-field sentiment */ ]
    },
    "translation": {
      "targetLanguage": "en",
      "translatedFields": { /* field-by-field translations */ }
    },
    "insights": {
      "npsScore": 9,
      "npsCategory": "Promoter | Passive | Detractor",
      "themes": ["customer-service", "product-quality"],
      "completeness": 0.95,
      "flaggedIssues": []
    }
  },
  "metadata": { /* from Silver + enrichment metadata */ },
  "enrichedAt": "2024-12-07T10:01:00Z"
}
```

**Indexing Policy (gold-enriched-documents)**:
```json
{
  "indexingMode": "consistent",
  "automatic": true,
  "includedPaths": [
    { "path": "/documentType/*" },
    { "path": "/metadata/companyName/*" },
    { "path": "/metadata/extractedAt/*" },
    { "path": "/enrichment/sentimentAnalysis/overall/*" },
    { "path": "/enrichment/insights/npsScore/*" },
    { "path": "/enrichment/insights/npsCategory/*" },
    { "path": "/enrichment/insights/themes/*" },
    { "path": "/enrichedAt/*" }
  ],
  "excludedPaths": [
    { "path": "/extractedData/*" },
    { "path": "/enrichment/translation/translatedFields/*" }
  ]
}
```

### 3. Azure Language Services (Cognitive Services)
```bicep
// Cognitive Service
- SKU: S (Standard)
- Kind: TextAnalytics
- Features Used:
  * Sentiment Analysis (supports 47+ languages)
  * Language Detection
  * Key Phrase Extraction
  * Text Translation API
```

**Supported Languages**: Auto-detect (Japanese, English, Chinese, Spanish, etc.)

### 4. Change Feed Configuration
```bicep
// Cosmos DB Change Feed settings
- Source Container: silver-extracted-documents
- Lease Container: leases
- Feed Poll Interval: 5000ms (5 seconds)
- Start From Beginning: false (process only new documents)
- Max Items Per Invocation: 100
```

---

## Report Layer Infrastructure Requirements

**Note**: Report APIs are deployed in the same Function App as Silver and Gold layers (see above).

### HTTP Report Endpoints

**Endpoints**:
```
GET  /api/reports/bank-survey/{id}/html
POST /api/reports/bank-survey/batch/html

GET  /api/reports/workshop-survey/{id}/html
POST /api/reports/workshop-survey/batch/html

GET  /api/reports/hygiene-form/{id}/html
POST /api/reports/hygiene-form/batch/html

GET  /api/reports/general-form/{id}/html
POST /api/reports/general-form/batch/html
```

**Required App Settings**:
```
// Same as Gold layer (reads from gold-enriched-documents)
COSMOS_DB_CONNECTION_STRING = "<cosmos-connection-string>"
COSMOS_DB_DATABASE_NAME = "mustrustDataPlatform"
COSMOS_DB_GOLD_CONTAINER = "gold-enriched-documents"
```

---

## Resource Summary Table

| Resource Type | Resource Name | SKU/Tier | Purpose | Layer |
|--------------|---------------|----------|---------|-------|
| Function App | `func-mustrust-analyzer-{customer}-{env}` | Premium EP1 or Consumption | Silver extraction + Gold enrichment + Reports | All |
| Cosmos DB Account | `cosmos-mustrust-{customer}-{env}` | Standard | NoSQL database (per customer) | Both |
| Cosmos DB Container | `silver-extracted-documents` | Autoscale (400-4000 RU/s) | Extracted documents | Silver |
| Cosmos DB Container | `gold-enriched-documents` | Autoscale (400-4000 RU/s) | Enriched documents | Gold |
| Cosmos DB Container | `leases` | 400 RU/s (manual) | Change feed tracking | Gold |
| Document Intelligence | `surveyformextractor2` (SHARED) | S0 Standard | OCR + custom models (shared) | Silver |
| Custom Vision | `circleMarkerRecognizer` (SHARED) | S0 Standard | Circle detection (shared) | Silver |
| Language Services | `lang-mustrust-{customer}-{env}` | S Standard | Sentiment + Translation (per customer) | Gold |
| Storage Account | `stmustrust{customer}{env}` | Standard LRS | Queue + Bronze blobs (per customer) | Bronze |
| Storage Queue | `bronze-document-queue` | N/A | Trigger Silver processing | Bronze→Silver |

---

## Deployment Configuration Points

### 1. Partition Key Strategy
All Cosmos DB containers use `/documentType` as partition key:
- Evenly distributes load across document types
- Enables category-specific queries
- Supports plugin framework (easy to add new categories)

### 2. Change Feed Configuration
```javascript
// In function.json for GoldEnrichmentProcessor
{
  "type": "cosmosDBTrigger",
  "name": "documents",
  "direction": "in",
  "connectionStringSetting": "COSMOS_DB_CONNECTION_STRING",
  "databaseName": "mustrustDataPlatform",
  "collectionName": "silver-extracted-documents",
  "leaseCollectionName": "leases",
  "createLeaseCollectionIfNotExists": true,
  "startFromBeginning": false,
  "feedPollDelay": 5000,
  "maxItemsPerInvocation": 100
}
```

### 3. Autoscale Settings
**Recommended Throughput**:
- Development: 400-1000 RU/s autoscale
- Production: 400-4000 RU/s autoscale
- Leases container: 400 RU/s manual (fixed)

### 4. Custom Model Deployment - SHARED MODELS
**Document Intelligence Custom Models** (already trained and shared):
1. Models are trained once in the shared `surveyformextractor2` resource
2. Model IDs are configured in Function App settings during deployment
3. **No model training or copying required per customer**
4. Update ExtractorRegistry.js with shared model IDs (same across all customers)

**Custom Vision Models** (already trained and shared):
1. Models are trained once in the shared `circleMarkerRecognizer` project
2. Prediction endpoint/keys are configured in Function App settings
3. **No model training or copying required per customer**
4. All customers use the same published iteration (Iteration6)

### 5. Network Security (Optional)
```bicep
// Recommended for production
- Enable Private Endpoints for Cosmos DB
- Enable VNet Integration for Function Apps
- Use Managed Identity instead of connection strings
- Store secrets in Azure Key Vault
```

---

## Dependencies Between Layers

### Bronze → Silver
- **Trigger**: Azure Storage Queue (`bronze-document-queue`)
- **Input**: Blob reference from Bronze storage
- **Output**: JSON document to `silver-extracted-documents`

### Silver → Gold
- **Trigger**: Cosmos DB Change Feed (`silver-extracted-documents`)
- **Input**: Extracted JSON from Silver
- **Output**: Enriched JSON to `gold-enriched-documents`

### Gold → Reports
- **Trigger**: HTTP request
- **Input**: Document ID or filter criteria
- **Output**: HTML/JSON report

---

## Cost Estimation (Monthly, Production)

### Per Customer Environment Costs

| Service | Configuration | Est. Cost (USD) |
|---------|--------------|-----------------|
| Function App (Premium EP1) | ~730 hours/month, hosts all functions | ~$150 |
| Cosmos DB (2 containers) | 4000 RU/s autoscale each | ~$280 |
| Language Services | S tier, ~10K requests | ~$20 |
| Storage (Bronze) | Standard LRS | ~$10 |
| **Total per customer** | | **~$460/month** |

### Shared Resources (One-time, all customers)

| Service | Configuration | Est. Cost (USD) |
|---------|--------------|-----------------|
| Document Intelligence (SHARED) | S0, ~1000 pages/month per customer | ~$10 per 1000 pages |
| Custom Vision (SHARED) | S0, prediction calls | ~$2 per 1000 predictions |
| **Shared AI total** | Scales with usage across all customers | **Variable** |

**Cost Optimization Benefits**:
- **70-80% reduction in AI costs** by sharing Document Intelligence and Custom Vision
- Previous architecture: $200-700/month per customer with dedicated AI resources
- Current architecture: $60-200/month per customer (AI usage billed at shared resource)
- Use Consumption plan for Function Apps (pay per execution)
- Start with 400-1000 RU/s autoscale for Cosmos DB
- Monitor and adjust based on actual usage

**Billing Separation**:
- Customer data isolation: Each customer has their own Cosmos DB and Storage
- Shared AI models: Usage tracked at central resource, can be allocated by tags/metadata
- Language Services: Per-customer resource for easier billing attribution

---

## Bicep Template Structure

### Recommended Module Organization
```
bicep/
├── main.bicep                    # Main orchestration
├── modules/
│   ├── silver-layer.bicep        # Silver infrastructure
│   ├── gold-layer.bicep          # Gold infrastructure
│   ├── cosmos-db.bicep           # Cosmos DB account + containers
│   ├── function-app.bicep        # Function App module
│   ├── cognitive-services.bicep  # AI services module
│   └── storage.bicep             # Storage account + queue
└── parameters/
    ├── dev.parameters.json
    ├── staging.parameters.json
    └── prod.parameters.json
```

### Key Bicep Parameters
```bicep
param customerName string // e.g., 'yys'
param environment string = 'dev' // dev, staging, prod
param location string = 'japaneast'
param deploySilverGold bool = false // Set to true to deploy analyzer layer

// Cosmos DB (per customer)
param cosmosDbAccountName string = 'cosmos-mustrust-${customerName}-${environment}'
param cosmosDatabaseName string = 'mustrustDataPlatform'

// Function App (hosts Silver, Gold, and Reports) - per customer
param functionAppName string = 'func-mustrust-analyzer-${customerName}-${environment}'
param appServicePlanSku string = 'Y1' // Consumption (or EP1 for Premium)

// AI Services - PER CUSTOMER
param languageServiceAccountName string = 'lang-mustrust-${customerName}-${environment}'

// AI Services - SHARED (NOT created by Bicep, referenced only)
// Document Intelligence: surveyformextractor2 (in hcsGroup)
// Custom Vision: circleMarkerRecognizer (in hcsGroup)
// These are manually configured in Function App settings after deployment

// Shared Custom Model IDs (same for all customers)
param sharedDocIntelligenceEndpoint string = '' // Placeholder, set in app settings
param sharedCustomVisionEndpoint string = '' // Placeholder, set in app settings
```

---

## Next Steps for Bicep Creation

1. ✅ **Create Cosmos DB module** with 3 containers (silver, gold, leases)
2. ✅ **Create Function App module** with app settings injection
3. ✅ **Create Language Services module** (per customer) - Document Intelligence and Custom Vision are SHARED, not created
4. ✅ **Create main.bicep** to orchestrate all modules with `deploySilverGold` flag
5. ✅ **Create parameter files** for customer environments (e.g., yys-dev)
6. ✅ **Add outputs** for connection strings and endpoints
7. ✅ **Create deployment script** with Azure CLI commands
8. **Manual Step**: Configure shared AI service credentials in Function App settings:
   - `DOCUMENT_INTELLIGENCE_ENDPOINT` → from `surveyformextractor2`
   - `DOCUMENT_INTELLIGENCE_KEY` → from `surveyformextractor2`
   - `CUSTOM_VISION_PREDICTION_ENDPOINT` → from `circleMarkerRecognizer`
   - `CUSTOM_VISION_PREDICTION_KEY` → from `circleMarkerRecognizer`
   - `CUSTOM_VISION_PROJECT_ID` → from `circleMarkerRecognizer`

---

## Plugin Framework Benefits

The infrastructure supports **easy extensibility**:

✅ **Add new document types** without infrastructure changes
- Register new extractor in ExtractorRegistry.js
- Register new enricher in EnricherRegistry.js  
- Same Cosmos DB containers, same functions

✅ **Train new custom models**
- Train in Document Intelligence Studio
- Update app settings with new model ID
- Update extractor plugin configuration

✅ **Add new AI enrichments**
- Update enricher logic in EnricherRegistry.js
- Same Language Services, same Gold container

---

## References

- **Architecture Documentation**: `ARCHITECTURE.md`
- **Extractor Plugin Guide**: `HOW_TO_ADD_NEW_EXTRACTOR.md`
- **Report API Reference**: `REPORT_GENERATION_API.md`
- **Plugin Registry Code**: `src/functions/silver/ExtractorRegistry.js`, `src/functions/gold/EnricherRegistry.js`

---

**Document Version**: 1.0  
**Last Updated**: 2024-12-07  
**Author**: mustrust Data Platform Team
