# MusTrusT® Data Platform - Infrastructure

This repository provides **fully automated, repeatable infrastructure deployment** for the MusTrusT® Data Platform using Azure Bicep.

## 🏗️ What This Deploys

This infrastructure supports a complete **Medallion Architecture** (Bronze → Silver → Gold) data processing pipeline:

### Azure Resources
- **Storage Accounts** (2):
  - `stmustrustweb{customer}{env}` - Frontend hosting + web uploads ($web, web-input-files)
  - `stmustrust{customer}{env}` - Data processing (bronze/silver/gold containers, queues)
- **Function Apps** (2):
  - `func-mustrust-preprocessor-{customer}-{env}` - Bronze layer (Python 3.11)
  - `func-mustrust-analyzer-{customer}-{env}` - Silver + Gold layers (Node.js 18)
- **Cosmos DB** - Document storage (silver-extracted-documents, gold-enriched-documents)
- **Event Grid** - File upload triggers
- **AI Services**:
  - Document Intelligence (2 instances for preprocessor + analyzer)
  - Custom Vision - Symbol detection
  - Language/Translator - Text analysis & translation

### GitHub Integration
- Automatic deployment credentials (Service Principal)
- GitHub Actions secrets configuration
- CI/CD pipeline support

## 🎯 Quick Start - One Command Setup

```bash
./setup-environment.sh \
  --customer yys \
  --environment prod \
  --github-repo your-org/mustrust-functions
```

**What this does:**
✅ Deploys all Azure infrastructure (Storage, Function App, Event Grid)  
✅ Creates GitHub deployment credentials  
✅ Configures automatic file processing triggers  
✅ Provides GitHub setup instructions  

**Environments:** `dev`, `test`, `prod`

For detailed workflow, see [Complete Setup Guide](#-complete-workflow) below.

---

## 🎉 Summary

**One command to set up everything:**
```bash
./setup-environment.sh --customer yys --environment prod --github-repo myorg/app
```

See full documentation in [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)
