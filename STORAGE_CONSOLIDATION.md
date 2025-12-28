# Storage Account Consolidation Guide

## Overview

Consolidated infrastructure from **3 storage accounts** to **2 storage accounts** to reduce costs and simplify architecture.

## Architecture Changes

### Before (3 Storage Accounts)
```
┌─────────────────────────────────────────────────────────┐
│ stmustrustwebyyysdev                                    │
│ - Static website ($web)                                 │
│ - File uploads (web-input-files)                        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ stpreprocyyysdev (REDUNDANT)                            │
│ - Preprocessor staging (preprocessor-uploads)           │
│ - Background processing (preprocessor-processing)       │
│ - Processing queue (preprocessor-file-processing-queue) │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ stmustrustyyysdev                                       │
│ - Bronze layer (bronze-processed-files)                 │
│ - Silver/Gold processing                                │
│ - Dictionaries (dictionaries)                           │
└─────────────────────────────────────────────────────────┘
```

### After (2 Storage Accounts)
```
┌─────────────────────────────────────────────────────────┐
│ stmustrustwebyyysdev (Frontend + Preprocessor)          │
│ - Static website ($web)                                 │
│ - File uploads (web-input-files)                        │
│ - Preprocessor staging (preprocessor-uploads)           │
│ - Background processing (preprocessor-processing)       │
│ - Processing queue (preprocessor-file-processing-queue) │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ stmustrustyyysdev (Analyzer Only)                       │
│ - Bronze layer (bronze-processed-files)                 │
│ - Silver/Gold processing                                │
│ - Dictionaries (dictionaries)                           │
└─────────────────────────────────────────────────────────┘
```

## Why This Change?

1. **Cost Savings**: One less storage account to pay for
2. **Logical Grouping**: Frontend and Preprocessor naturally belong together
3. **Simplified Management**: Fewer resources to monitor and maintain
4. **Clear Separation**: Preprocessor (user-facing) vs Analyzer (backend processing)

## File Changes

### Bicep Infrastructure

#### `bicep/modules/storage-web.bicep`
Added preprocessor containers and queue to web storage:
- Container: `preprocessor-uploads`
- Container: `preprocessor-processing`
- Queue: `preprocessor-file-processing-queue`

#### `bicep/main.bicep`
- Removed `preprocessorStorageAccountName` variable
- Removed `preprocessor-storage.bicep` module deployment
- Updated app service to use web storage connection string

#### `bicep/modules/app-service-preprocessor.bicep`
- Removed `preprocessorStorageAccountName` parameter
- Removed preprocessor storage account reference
- Changed `BRONZE_STORAGE_CONNECTION_STRING` to use web storage

### Deployment Scripts

#### `setup-environment.sh`
- Removed `PREPROCESSOR_STORAGE_ACCOUNT` variable
- Updated resource descriptions to reflect 2 storage accounts
- Updated output messages

## Deployment Steps

### 1. Deploy Updated Infrastructure

```bash
cd MusTrusTDataPlatformInfra
./setup-environment.sh --customer yys --environment dev --with-analyzer
```

This will:
- Create/update web storage with preprocessor containers
- Skip creating separate preprocessor storage
- Configure app service to use web storage

### 2. Verify Storage Accounts

Check Azure Portal - you should see only **2 storage accounts**:
- `stmustrustwebyyysdev`
- `stmustrustyyysdev`

### 3. Clean Up Old Storage (Manual)

If `stpreprocyyysdev` still exists from previous deployments:

```bash
az storage account delete \
  --name stpreprocyyysdev \
  --resource-group rg-mustrust-yys-dev \
  --yes
```

### 4. Verify App Service Configuration

```bash
az webapp config appsettings list \
  --name app-mustrust-preprocessor-yys-dev \
  --resource-group rg-mustrust-yys-dev \
  --query "[?name=='BRONZE_STORAGE_CONNECTION_STRING'].value" -o tsv
```

Should show connection string for `stmustrustwebyyysdev`.

## Environment Variables

No changes needed in application code. The app service still uses:
- `BRONZE_STORAGE_CONNECTION_STRING` - now points to web storage

The preprocessor server.js already uses this variable correctly for:
- Uploading to `preprocessor-uploads` container
- Processing from `preprocessor-processing` container
- Queueing to `preprocessor-file-processing-queue`

## Testing Checklist

After deployment:

- [ ] Frontend loads correctly
- [ ] File upload works (saves to web storage)
- [ ] Preprocessor staging works (background processing)
- [ ] Files forward to analyzer (bronze layer)
- [ ] Dictionary management works
- [ ] Only 2 storage accounts in Azure Portal

## Rollback Plan

If issues occur, redeploy with original 3-storage setup:

1. Revert commit: `git revert ab968d4`
2. Redeploy: `./setup-environment.sh --customer yys --environment dev --with-analyzer`

## Cost Impact

**Estimated Savings**: ~$20-30/month per environment
- Storage account base cost: ~$0.02/GB
- Transaction costs reduced (fewer cross-storage operations)
- Simplified monitoring = less operational overhead

## Migration Notes

### Existing Deployments

Existing deployments will automatically migrate on next infrastructure update:
1. Web storage gets new containers/queue
2. App service connection string updated
3. Old preprocessor storage becomes orphaned (safe to delete)

### Data Migration

No data migration needed:
- Preprocessor containers are ephemeral (staging only)
- All persistent data stays in analyzer storage
- Frontend static files already in web storage

## References

- Commit: `ab968d4` - Storage consolidation
- Issue: Identified during infrastructure review
- Decision: Consolidate preprocessor into web storage (not analyzer)
- Rationale: Frontend + Preprocessor are user-facing, Analyzer is backend
