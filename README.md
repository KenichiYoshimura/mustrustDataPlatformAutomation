# MusTrusT® Data Platform — Infra Runbook

This folder automates Azure infrastructure for MusTrusT® (storage, functions, Cosmos DB, AI services, and Easy Auth) via Bicep and helper scripts.

## Prereqs
- Azure CLI logged in (`az login`) with contributor rights to the target subscription.
- Bicep available to Azure CLI (bundled by default).
- For Easy Auth setup, permission to create an app registration in the tenant.

## What to run (happy path)
- Provision base infra + SP: [setup-environment.sh](setup-environment.sh) `--customer <name> --environment <dev|test|prod> [--with-analyzer] --github-repo <owner/repo>`
- Deploy application code: publish preprocessor/analyzer from their repos; deploy frontend static site.
- Configure analyzer AI keys: [configure-analyzer-ai.sh](configure-analyzer-ai.sh) (only when analyzer is deployed).
- Secure preprocessor with Easy Auth: [setup-easy-auth.sh](setup-easy-auth.sh) (can be run anytime after the app exists).

## Script catalog (kept)
- [setup-environment.sh](setup-environment.sh): updates `bicep/main.bicepparam`, sets subscription, deploys Bicep, and creates GitHub SP creds (writes `.azure-credentials-<customer>-<env>.json`; delete after adding to GitHub secrets).
- [deploy.sh](deploy.sh): runs the Bicep deployment using values from `bicep/main.bicepparam` (called by setup-environment; rarely run directly).
- [configure-analyzer-ai.sh](configure-analyzer-ai.sh): pulls shared AI service keys and applies analyzer app settings. (Contains hard-coded keys today—move to Key Vault/inputs later.)
- [setup-easy-auth.sh](setup-easy-auth.sh): creates AAD app registration, client secret, and enables Easy Auth on the preprocessor App Service.
- [cleanup-environment.sh](cleanup-environment.sh): deletes RG + SP, purges soft-deleted Cosmos/AI resources for a clean redeploy.
- [verify-analyzer-config.sh](verify-analyzer-config.sh): compares analyzer app settings across two environments.

## Removed scripts
- `setup-translator.sh` (redundant; translator is handled via Bicep and `configure-analyzer-ai.sh`).
- `setup-eventgrid.sh` (Event Grid no longer used for document processing).
- Temporary SP credential dumps (`.azure-credentials-*.json`) removed; regenerate by re-running [setup-environment.sh](setup-environment.sh) if needed.

## Minimal runbook
1) `./setup-environment.sh --customer <name> --environment <env> [--with-analyzer] --github-repo <owner/repo>`
2) Deploy code (preprocessor webapp + frontend; analyzer if enabled).
3) If analyzer enabled: `./configure-analyzer-ai.sh --customer <name> --environment <env>`.
4) Optional: `./setup-easy-auth.sh --customer <name> --environment <env>`.
5) Optional validation: `./verify-analyzer-config.sh --customer <name> [--env1 dev --env2 prod]`.
6) Cleanup (when decommissioning): `./cleanup-environment.sh --customer <name> --environment <env>`.

For deeper details, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) and [DEPLOYMENT-STEPS.md](DEPLOYMENT-STEPS.md).
