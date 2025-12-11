# Must Trust Data Platform Infrastructure - YYS DEV Environment

## Resource Names

### Resource Group
- **Name**: `rg-mustrust-yys-dev`
- **Location**: Japan East

### Storage Accounts

#### Web Storage (Frontend & Preprocessor)
- **Name**: `stmustrustwebyysdev`
- **Purpose**: File uploads and static website hosting
- **Containers**:
  - `web-input-files` - Where frontend uploads files
  - `$web` - Static website hosting for frontend
  - `func-mustrust-preprocessor-yys-dev` - Function deployment container

#### Analyzer Storage (Processing & Data)
- **Name**: `stmustrustyysdev`
- **Purpose**: Data processing and storage
- **Containers**:
  - `bronze-processed-files` - Processed files from preprocessor
  - `bronze-invalid-files` - Invalid/failed files
- **Queues**:
  - `bronze-file-processing-queue` - Processing queue for analyzer

### Function Apps

#### Preprocessor Function
- **Name**: `func-mustrust-preprocessor-yys-dev`
- **Runtime**: Python 3.11 (Flex Consumption)
- **Storage**: Web Storage (`stmustrustwebyysdev`)
- **Environment Variables**:
  - `AzureWebJobsStorage` - Web storage connection (read from web-input-files)
  - `ANALYZER_STORAGE_CONNECTION_STRING` - Analyzer storage connection (write to bronze-*)
- **Functions**:
  - `EventGridTrigger` - Processes files from web-input-files
  - `upload` (HTTP) - Accepts file uploads from frontend

#### Analyzer Function
- **Name**: `func-mustrust-analyzer-yys-dev`
- **Runtime**: Node.js (Flex Consumption)
- **Storage**: Analyzer Storage (`stmustrustyysdev`)
- **Environment Variables**:
  - `AzureWebJobsStorage` - Analyzer storage connection
  - `COSMOS_CONNECTION_STRING` - Cosmos DB connection
  - `LANGUAGE_SERVICE_ENDPOINT` - Azure AI Language endpoint
  - `LANGUAGE_SERVICE_KEY` - Azure AI Language key

### Cosmos DB (if deploySilverGold = true)
- **Account Name**: `cosmos-mustrust-yys-dev`
- **Database**: `mustrustDataPlatform`
- **Containers**:
  - `silver-extracted-documents` - Document extraction results
  - `gold-enriched-documents` - Enriched and categorized documents
  - `leases` - Change feed lease tracking

### Azure AI Services (if deploySilverGold = true)
- **Language Service**: `lang-mustrust-yys-dev`
- **SKU**: S (Standard)
- **Features**: Sentiment Analysis, Translation

### Application Insights
- **Preprocessor**: `func-mustrust-preprocessor-yys-dev-insights`
- **Analyzer**: `func-mustrust-analyzer-yys-dev-insights`
- **Log Analytics**: 
  - `func-mustrust-preprocessor-yys-dev-logs`
  - `func-mustrust-analyzer-yys-dev-logs`

## Architecture Flow

### 1. Frontend Upload
```
User → Frontend (Static Web App) 
     → POST /api/upload 
     → Preprocessor Function 
     → Uploads to web-input-files (stmustrustwebyysdev)
```

### 2. File Processing (Preprocessor)
```
EventGrid (web-input-files blob created)
     → Preprocessor Function EventGridTrigger
     → Read from: stmustrustwebyysdev/web-input-files
     → Process: PDF → Images, Validation, etc.
     → Write to: stmustrustyysdev/bronze-processed-files
     → Send message to: stmustrustyysdev/bronze-file-processing-queue
```

### 3. Document Analysis (Analyzer)
```
Queue Trigger (bronze-file-processing-queue)
     → Analyzer Function (Silver Layer)
     → Document Intelligence extraction
     → Write to: Cosmos DB/silver-extracted-documents
```

### 4. Document Enrichment (Analyzer)
```
Cosmos Change Feed (silver-extracted-documents)
     → Analyzer Function (Gold Layer)
     → AI enrichment (categorization, sentiment, etc.)
     → Write to: Cosmos DB/gold-enriched-documents
```

### 5. Frontend Access
```
Frontend → GET /api/gold/documents (Analyzer Function)
        → Read from: Cosmos DB/gold-enriched-documents
        → Display in UI
```

## Deployment Commands

### Deploy Infrastructure
```bash
cd MusTrusTDataPlatformInfra
./deploy.sh
```

### Deploy Preprocessor Function
```bash
cd mustrustDataPlatformProcessor
func azure functionapp publish func-mustrust-preprocessor-yys-dev
```

### Deploy Analyzer Function
```bash
cd mustrustDataPlatformAnalyzer
func azure functionapp publish func-mustrust-analyzer-yys-dev
```

### Deploy Frontend
```bash
cd mustrustDataPlatformProcessor
./deploy-frontend.sh stmustrustwebyysdev
```

### Configure EventGrid (after first deployment)
```bash
cd MusTrusTDataPlatformInfra
./setup-eventgrid.sh
```

## Frontend URLs

### Static Website
- **Primary**: `https://stmustrustwebyysdev.z11.web.core.windows.net/`
- **Custom Domain**: (Configure if needed)

### API Endpoints

#### Preprocessor API
- **Base URL**: `https://func-mustrust-preprocessor-yys-dev.azurewebsites.net`
- **Upload**: `POST /api/upload`

#### Analyzer API
- **Base URL**: `https://func-mustrust-analyzer-yys-dev.azurewebsites.net`
- **Documents**: `GET /api/gold/documents`
- **Categories**: `GET /api/gold/categories`
- **Reports**: `GET /api/reports/{type}/{id}/html`

## Storage Account Separation

### Why Two Storage Accounts?

1. **Security**: Frontend has no access to processed data
2. **Cost Management**: Separate billing for web vs. data processing
3. **Scalability**: Independent scaling for uploads vs. processing
4. **Maintenance**: Can update/maintain independently

### Cost Optimization

- Both using `Standard_LRS` (cheapest redundancy)
- Web storage: Optimized for hot access (uploads)
- Analyzer storage: Can use cool tier for archive if needed

## Next Steps

1. ✅ Infrastructure defined
2. ⬜ Deploy infrastructure (`./deploy.sh`)
3. ⬜ Deploy preprocessor code
4. ⬜ Deploy analyzer code
5. ⬜ Deploy frontend
6. ⬜ Configure EventGrid subscription
7. ⬜ Test end-to-end flow
