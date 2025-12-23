# MusTrusT Data Platform - Authentication & Authorization Strategy

**Date:** December 18, 2025  
**Status:** Validated & Approved (ChatGPT Review)  
**Approach:** Easy Auth + Managed Identity (Simple & Secure)

---

## Executive Summary

Instead of building a complex Front Door + JWT architecture, we're implementing a **simpler, Azure-native approach** that is:
- ✅ **Secure:** Production-grade Azure security model
- ✅ **Simple:** Minimal code changes, uses built-in Azure features
- ✅ **Scalable:** Works for multi-service architecture

**Architecture Overview:**
```
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │
       │ Easy Auth (Azure AD Login)
       ↓
┌─────────────────────────────────┐
│ Preprocessor Web App            │
│ - Frontend (static HTML/CSS/JS) │
│ - Proxy Backend (Node.js)       │
│ - User logged in via Azure AD   │
└────────────┬────────────────────┘
             │
             │ Managed Identity Token
             ↓
      ┌──────────────────┐
      │ Analyzer Web App │
      │ - Protected APIs │
      │ - Validates token│
      └──────────────────┘
```

---

## Why This Approach (Not Front Door)

| Aspect | Front Door Approach | This Approach |
|--------|-------------------|---------------|
| Complexity | High (response rewriting, routing rules) | Low (Azure built-ins) |
| Code Changes | Moderate | Minimal |
| Risk | Medium (new infrastructure) | Low (standard patterns) |
| Security | Good | Excellent |
| Maintenance | Complex | Simple |
| Time to Implement | 8+ hours | 2-3 hours |

---

## The 4-Step Implementation Plan

### **Step 1: Enable Easy Auth on Preprocessor (User Login)**

**What it does:**
- Users accessing Preprocessor are redirected to Azure AD login
- After login, users have a session cookie (Easy Auth manages this)
- User identity headers are injected (X-MS-CLIENT-PRINCIPAL, etc.)
- No code changes needed

**Command:**
```bash
az webapp auth update \
  --resource-group rg-mustrust-yys-dev \
  --name func-mustrust-preprocessor-yys-dev \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-client-id 01e874b5-27e7-4b9f-aa77-633c5b4459bb \
  --aad-allowed-issuers "https://sts.windows.net/cafcba3c-2cc4-45cb-9a24-cfc71a629160/"
```

**Result:** ✅ User is logged in and can access Preprocessor

**Important:** Easy Auth only protects Preprocessor. It does NOT protect calls from Preprocessor → Analyzer. Steps 2-3 fix that.

---

### **Step 2: Assign Managed Identity to Preprocessor**

**What it does:**
- Gives the Preprocessor web app a system-assigned identity (like a service account)
- Azure automatically manages the identity lifecycle (no secrets to store)
- This identity can get tokens to call other Azure services

**Commands:**
```bash
# Assign Managed Identity to Preprocessor
az webapp identity assign \
  --resource-group rg-mustrust-yys-dev \
  --name func-mustrust-preprocessor-yys-dev

# Get the identity's principal ID
IDENTITY_ID=$(az webapp identity show \
  --resource-group rg-mustrust-yys-dev \
  --name func-mustrust-preprocessor-yys-dev \
  --query principalId -o tsv)

# Grant this identity permission to access Analyzer
az role assignment create \
  --assignee-object-id $IDENTITY_ID \
  --role "Web Plan Contributor" \
  --scope /subscriptions/6a6d110d-80ef-424a-b8bb-24439063ffb2/resourceGroups/rg-mustrust-yys-dev/providers/Microsoft.Web/sites/func-mustrust-analyzer-yys-dev
```

**Result:** ✅ Preprocessor can now request tokens to call Analyzer

---

### **Step 3: Update Preprocessor Backend Code (Use Managed Identity)**

**What it does:**
- When Preprocessor backend needs to call Analyzer APIs, it uses the Managed Identity to get a token
- The token is sent in the Authorization header
- No user credentials are involved

**Code Example (Node.js):**
```javascript
const { DefaultAzureCredential } = require("@azure/identity");

const credential = new DefaultAzureCredential();

async function callAnalyzerAPI(endpoint, data) {
  try {
    // Get token using Managed Identity
    const token = await credential.getToken(
      "https://management.azure.com/.default"
    );

    // Call Analyzer API with token
    const response = await fetch(
      `https://func-mustrust-analyzer-yys-dev.azurewebsites.net${endpoint}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token.token}`
        },
        body: JSON.stringify(data)
      }
    );

    return await response.json();
  } catch (error) {
    console.error("API call failed:", error);
    throw error;
  }
}

// Usage in your endpoint
app.post("/api/process", async (req, res) => {
  const result = await callAnalyzerAPI("/api/analyze", req.body);
  res.json(result);
});
```

**Result:** ✅ Preprocessor can securely call Analyzer APIs

---

### **Step 4: Configure Analyzer to Validate Tokens (Critical!)**

**What it does:**
- Analyzer must validate the tokens that Preprocessor sends
- This ensures only authorized services can call Analyzer APIs

**Option A (Recommended): Enable Easy Auth on Analyzer**

```bash
az webapp auth update \
  --resource-group rg-mustrust-yys-dev \
  --name func-mustrust-analyzer-yys-dev \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-client-id <analyzer-client-id>
```

**Then configure token validation:**
- Set `Allowed Token Audiences` to allow Preprocessor's identity
- This makes Easy Auth validate service-to-service tokens automatically

**Option B (Custom Code): Validate JWT in Your Code**

```javascript
const jwt = require("jsonwebtoken");

// Middleware to validate token
function validateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return res.status(401).json({ error: "Missing token" });
  }

  const token = authHeader.split(" ")[1];
  
  try {
    // Validate token signature and claims
    const decoded = jwt.verify(token, process.env.JWT_SECRET, {
      audience: "mustrust-analyzer-prod",
      issuer: "https://sts.windows.net/<tenant-id>/"
    });
    
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: "Invalid token" });
  }
}

// Apply to protected routes
app.post("/api/analyze", validateToken, (req, res) => {
  // Process request
});
```

**Result:** ✅ Analyzer validates all incoming tokens and rejects unauthorized calls

---

## Security Model

| Layer | Auth Mechanism | Purpose | Secured By |
|-------|---|---|---|
| **User → Preprocessor** | Easy Auth (Azure AD) | User identity | Azure AD login |
| **Preprocessor Backend → Analyzer** | Managed Identity Token | Service identity | Azure RBAC + Token signature |
| **Analyzer** | Token validation | API access | JWT/Azure AD validation |

**Key Properties:**
- ✅ No passwords or secrets in code
- ✅ No user tokens forwarded to backend APIs
- ✅ Service acts as trusted backend (not impersonating users)
- ✅ Defense-in-depth (each layer has its own auth)

---

## Common Pitfalls to AVOID

### ❌ Mistake 1: Forwarding User Tokens to Analyzer
```javascript
// WRONG - Never do this!
const userToken = req.headers.authorization;
await fetch("analyzer-url", {
  headers: { "Authorization": userToken }  // ❌ DON'T
});
```
**Why:** User tokens should not be shared with backend services.

**Correct approach:** Use Managed Identity instead.

### ❌ Mistake 2: Relying Only on Easy Auth for Service-to-Service
Easy Auth protects incoming traffic only. It does NOT:
- Authenticate Preprocessor → Analyzer calls
- Validate tokens on Analyzer

You MUST add explicit token validation on Analyzer.

### ❌ Mistake 3: Using Function Keys or App Secrets
```javascript
// WRONG
const secret = "my-app-secret-123";  // ❌ Don't hardcode
```
**Why:** Secrets are hard to rotate and risk exposure.

**Correct approach:** Use Managed Identity (automatic rotation).

---

## Implementation Checklist

### Phase 1: Easy Auth on Preprocessor
- [ ] Get Preprocessor web app name: `func-mustrust-preprocessor-yys-dev`
- [ ] Get Azure AD client ID: `01e874b5-27e7-4b9f-aa77-633c5b4459bb`
- [ ] Run Easy Auth enable command
- [ ] Test: Visit Preprocessor URL → should redirect to login
- [ ] Verify: After login, X-MS-CLIENT-PRINCIPAL headers present

### Phase 2: Managed Identity Setup
- [ ] Assign Managed Identity to Preprocessor
- [ ] Get Preprocessor identity principal ID
- [ ] Grant role to access Analyzer
- [ ] Test: Check Preprocessor can request tokens

### Phase 3: Backend Code Changes
- [ ] Install Azure SDK: `npm install @azure/identity`
- [ ] Update Preprocessor backend to use DefaultAzureCredential
- [ ] Add token-based API calls to Analyzer
- [ ] Test: Call Analyzer API from Preprocessor
- [ ] Verify: Logs show successful token exchange

### Phase 4: Analyzer Token Validation
- [ ] Enable Easy Auth on Analyzer (Option A)
- [ ] OR implement custom token validation (Option B)
- [ ] Test: Call Analyzer with valid token → 200 OK
- [ ] Test: Call Analyzer without token → 401 Unauthorized
- [ ] Test: Call Analyzer with invalid token → 401 Unauthorized

---

## Architecture Validation (ChatGPT Approved ✅)

**Verdict:** Production-ready design
- ✅ **Secure:** Azure AD + Managed Identity
- ✅ **Simple:** Minimal complexity vs. Front Door
- ✅ **Scalable:** Standard Azure patterns
- ✅ **Maintainable:** Clear trust boundaries

**Why Better Than Complex Alternatives:**
- ❌ ~~Front Door~~ (unnecessary for this architecture)
- ❌ ~~JWT tokens~~ (Azure tokens handle this)
- ❌ ~~Response rewriting~~ (not needed)
- ✅ **Managed Identity** (Azure's standard for this use case)

---

## Next Steps

1. **Identify exact web app names** in your Azure subscription
2. **Implement Step 1:** Enable Easy Auth on Preprocessor
3. **Implement Step 2:** Assign Managed Identity
4. **Implement Step 3:** Update Preprocessor code
5. **Implement Step 4:** Configure Analyzer token validation
6. **Test end-to-end:** User login → API call → Response

---

## References

- [Azure Managed Identity Documentation](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)
- [App Service Authentication](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Azure SDK for JavaScript (DefaultAzureCredential)](https://learn.microsoft.com/en-us/javascript/api/@azure/identity/defaultazurecredential)

---

**Document Status:** Ready for implementation  
**Last Updated:** 2025-12-18
