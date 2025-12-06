# Simple Storage Deployment

## What This Does

Creates Azure resources in a single resource group:
- **Storage Account** with 2 blob containers:
  - `bronze-input` - for uploading raw files
  - `bronze-processed` - for processed/archived data
- **Function App** (Node.js 20, Consumption plan) - for processing data

## Quick Start

### 1. Edit Settings

Open `bicep/main.bicepparam` and change:
```bicep
param customerName = 'yys'      // ← Change to your company name
param environment = 'dev'       // ← Change to: dev, test, or prod
```

**This is your single source of truth for all deployment settings.**

### 2. Login to Azure
```bash
az login
```

### 3. (Optional) Set Subscription
```bash
# Check current subscription
az account show

# Change if needed
az account set --subscription "Your Subscription Name"
```

### 4. Deploy

**Simple way:**
```bash
./deploy.sh
```

**With specific subscription:**
```bash
./deploy.sh --subscription "12345678-1234-1234-1234-123456789abc"
```

**Or use environment variable:**
```bash
export AZURE_SUBSCRIPTION_ID="12345678-1234-1234-1234-123456789abc"
./deploy.sh
```

**To change customer/environment:** Edit `bicep/main.bicepparam` (single source of truth)

That's it! You'll get:
- A resource group: `rg-mustrust-{yourname}-{env}`
- A storage account with 2 containers: `bronze-input` and `bronze-processed`
- A Function App: `func-mustrust-{yourname}-{env}`

Where `{env}` is whatever you set (dev, test, or prod)

## What You'll See

```
🚀 MusTrusT Storage Deployment
===============================

✅ Logged in as: your@email.com
✅ Subscription: Your Subscription

📦 Deploying storage account...

✅ Deployment Complete!
=======================
resourceGroupName: rg-mustrust-contoso-dev
storageAccountName: stcontosodevxyz123
storageAccountId: /subscriptions/.../storageAccounts/stcontosodevxyz123
```

## Files

Only 3 files matter:

1. **bicep/main.bicepparam** - Your settings (edit the customerName)
2. **bicep/main.bicep** - Creates resource group, storage, and function app
3. **bicep/modules/storage.bicep** - Storage account with 2 containers
4. **bicep/modules/function.bicep** - Function App definition

## What's Next?

After you understand this, you can add more services one at a time:
- Cosmos DB (for your data)
- Azure Functions (to process files)
- Document Intelligence (for OCR)

But for now, just storage!

## Delete Everything

```bash
az group delete --name rg-mustrust-{yourname}-{env} --yes
```

Replace `{yourname}` with your customerName and `{env}` with your environment.

Examples:
```bash
# Development
az group delete --name rg-mustrust-acme-dev --yes

# Test
az group delete --name rg-mustrust-acme-test --yes

# Production
az group delete --name rg-mustrust-acme-prod --yes
```
