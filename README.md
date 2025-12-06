# MusTrusT Repeatable Infrastructure & Deployment Setup

This repository provides **fully automated, repeatable setup** for the MusTrusT data platform infrastructure and application deployment.

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
