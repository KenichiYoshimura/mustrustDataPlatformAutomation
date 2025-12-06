# MusTrusT & Sentiment Analysis Platform Architecture

## 🚀 Quick Start - Infrastructure Deployment

To deploy the complete Azure infrastructure for this platform:

```bash
# 1. Login to Azure
az login

# 2. Configure parameters (edit customerName, environment, etc.)
# Edit: bicep/main.bicepparam

# 3. Deploy infrastructure
./deploy.sh   # macOS/Linux
# OR
.\deploy.ps1  # Windows PowerShell
```

📖 **For detailed deployment instructions, see [bicep/README.md](bicep/README.md)**

---

## ✅ Overview
This document describes the architecture for an enterprise-grade analytics platform that handles multiple data sources, including handwritten survey forms, hygiene records, and IoT telemetry from MusTrusT (ThingsBoard). It uses a Bronze–Silver–Gold layered approach for data organization and leverages Azure services for scalability, security, and analytics.

✅ Core Principles

Bronze–Silver–Gold data layering for clarity and scalability.
Cosmos DB as the primary Silver layer for structured JSON and fast UI queries.
Power BI Embedded for advanced analytics and insight discovery (future phase).
Azure-native services for ingestion, processing, and security.


✅ Architecture Components
1. Data Sources

Handwritten survey forms & hygiene records

Input: JPG, PNG, PDF
Processing: Azure Document Intelligence (OCR + form recognition)


IoT telemetry (MusTrusT via ThingsBoard)

Input: JSON via ThingsBoard API
Metrics: Temperature, humidity, oxygen level, etc.


Future sources

Additional sensors, new survey formats, daily operational logs




2. Data Layers
Bronze Layer

Raw files (images, PDFs) stored in Azure Blob Storage / ADLS Gen2
Organized in hierarchical folders by source and date:
/bronze/surveys/raw/YYYY-MM-DD/
/bronze/hygiene/raw/YYYY-MM-DD/



Silver Layer

Normalized JSON from OCR and IoT API
Stored in Azure Cosmos DB for flexibility and fast UI queries
Containers:

surveyResponses
hygieneRecords
iotTelemetry


Partition keys: customerId or shopId for scalability

Gold Layer (future)

Analytics-ready tables in Azure Synapse or Fabric Lakehouse
Fact tables:

fact_survey_response
fact_sensor_reading
fact_hygiene_record


Dimension tables:

dim_shop
dim_device
dim_time




3. Processing & Integration

Azure Functions / Data Factory

Move data from Bronze → Silver
Normalize JSON schema for surveys and hygiene records


IoT ingestion

Direct API calls from ThingsBoard → Silver (Cosmos DB)


Synapse Link

Expose Cosmos DB data for Power BI analytics without ETL




4. Analytics & UI
Current Phase

React + Node.js UI queries Cosmos DB directly for reporting
Filters: date range, shop, category, sensor type

Future Phase

Power BI Embedded dashboards inside React app
Insight discovery with AI visuals:

Key Influencers
Anomaly Detection
Decomposition Tree


Row-Level Security (RLS) for multi-tenant customers


5. Security

Authentication

Microsoft Entra ID (Azure AD) for workforce + B2B guest access
MSAL for React or App Service Easy Auth


Data Protection

Managed Identity + Key Vault for secrets
Conditional Access for enterprise compliance


Network

Azure Front Door + WAF for global edge security




✅ Data Flow Diagram (Text Representation)
[Handwritten Forms] → [Azure Blob (Bronze)] → [Document Intelligence OCR] → [Cosmos DB (Silver)]
[Hygiene Records]   → [Azure Blob (Bronze)] → [Document Intelligence OCR] → [Cosmos DB (Silver)]
[IoT Telemetry]     → [ThingsBoard API] → [Cosmos DB (Silver)]
                                      ↓
                              [Synapse Link]
                                      ↓
                              [Power BI Embedded (Gold)]
                                      ↓
                          [React/Node.js UI with Secure Auth]


✅ Why Cosmos DB for Silver

Handles semi-structured JSON easily
Low-latency queries for your UI
Scales globally for future customers
Analytics-ready via Synapse Link


✅ Next Steps

Set up Cosmos DB with containers for surveys, hygiene, IoT telemetry
Implement Bronze storage in Blob for raw files
Build data ingestion pipeline (Document Intelligence → Cosmos DB)
Secure your app with Entra ID authentication
Plan Power BI Embedded integration for advanced analytics