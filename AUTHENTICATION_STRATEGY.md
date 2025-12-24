# MusTrusT Data Platform - Authentication & Authorization Strategy

**Date:** December 18, 2025  
**Last Updated:** December 23, 2025  
**Status:** Phase 1 Complete | Phase 2-4 Outstanding  
**Current Phase:** End-to-End Testing with Anonymous APIs (Interim)  
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

### **Step 1: Enable Easy Auth on Preprocessor (User Login) ✅ COMPLETED**

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

**Status:** ✅ DONE - Users can log in with Azure AD credentials

---

### **Interim Approach: Anonymous Analyzer APIs (Current)**

**While Steps 2-4 are in development:**
- Analyzer APIs changed from `authLevel: 'function'` to `authLevel: 'anonymous'`
- Security model: Network isolation + Easy Auth on Preprocessor entry point
- Only authenticated Preprocessor users can trigger API calls to Analyzer
- Preprocessor backend makes calls without additional authentication tokens

**This approach allows:**
- ✅ End-to-end file upload/processing testing to work
- ✅ Validation of the full data pipeline
- ✅ Time to implement proper Managed Identity security

**⚠️ Important:** This is temporary. Proper inter-service authentication (Steps 2-4 below) should be implemented before production deployment.

---

### **Step 2: Assign Managed Identity to Preprocessor ⏳ OUTSTANDING**

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

# Get the identity's principal ID ⏳ OUTSTANDING
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

**Status:** ⏳ PENDING - Execute after Phase 1 validation

**Result:** ✅ Preprocessor can request tokens to call Analyzer

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

**Status:** ⏳ PENDING - Implement after Step 2 is complete

**Result:** ✅ Preprocessor can securely call Analyzer APIs

---

### **Step 4: Configure Analyzer to Validate Tokens (Critical!) ⏳ OUTSTANDING**

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
``Status:** ⏳ PENDING - Implement after Step 3 is complete

**Result:** ✅ Analyzer validates all incoming tokens and rejects unauthorized calls

---

## Current Security Posture

### Phase 1 (Current): Easy Auth + Anonymous APIs
| Component | Protection | Status |
|-----------|-----------|--------|
| User → Preprocessor | Easy Auth (Azure AD) | ✅ Active |
| Preprocessor Frontend | Azure AD session required | ✅ Active |
| Analyzer APIs | Anonymous (network isolated) | ✅ Active (interim) |
| Inter-service tokens | None (interim) | ⏳ Planned |

### Phase 2 (Next): Managed Identity + Token Validation
| Component | Protection | Status |
|-----------|-----------|--------|
| User → Preprocessor | Easy Auth (Azure AD) | ✅ Active |
| Preprocessor Backend | Managed Identity tokens | ⏳ To be implemented |
| Analyzer APIs | Token validation | ⏳ To be implemented |
| Inter-service auth | Full end-to-end | ⏳ To be implemented |

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
**Why:** User tokens should not be sha ✅ COMPLETE
- [x] Get Preprocessor web app name: `func-mustrust-preprocessor-yys-dev`
- [x] Get Azure AD client ID: `01e874b5-27e7-4b9f-aa77-633c5b4459bb`
- [x] Run Easy Auth enable command
- [x] Test: Visit Preprocessor URL → should redirect to login
- [x] Verify: After login, X-MS-CLIENT-PRINCIPAL headers present
- [x] Changed Analyzer APIs from 'function' to 'anonymous' auth level (interim)

### Phase 2: Managed Identity Setup ⏳ NEXT
- [ ] Assign Managed Identity to Preprocessor
- [ ] Get Preprocessor identity principal ID
- [ ] Grant role to access Analyzer
- [ ] Test: Check Preprocessor can request tokens

### Phase 3: Backend Code Changes ⏳ NEXT
- [ ] Install Azure SDK: `npm install @azure/identity`
- [ ] Update Preprocessor backend to use DefaultAzureCredential
- [ ] Add token-based API calls to Analyzer
- [ ] Test: Call Analyzer API from Preprocessor
- [ ] Verify: Logs show successful token exchange

### Phase 4: Analyzer Token Validation ⏳ NEXT
- [ ] Enable Easy Auth on Analyzer (Option A)
- [ ] OR implement custom token validation (Option B)
- [ ] Test: Call Analyzer with valid token → 200 OK
- [ ] Test: Call Analyzer without token → 401 Unauthorized
- [ ] Test: Call Analyzer with invalid token → 401 Unauthorized
- [ ] Change Analyzer APIs back from 'anonymous' to 'function' (or custom validation)

### Interim Testing (Current Phase)
- [x] Test end-to-end file upload with Easy Auth + anonymous APIs
- [x] Verify Preprocessor can call Analyzer endpoints
- [ ] Confirm data flows through complete pipeliner-yys-dev`
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
## Current Status Summary

**Phase 1 (Easy Auth on Preprocessor):** ✅ COMPLETE
- Users logging in with Azure AD ✅
- Preprocessor frontend protected ✅
- Analyzer APIs set to anonymous (interim) ✅

**Next Action:** Test end-to-end file upload functionality to validate Phase 1 before moving to Phase 2

**Phase 2-4 (Managed Identity + Token Validation):** ⏳ OUTSTANDING - NEXT TASKS AFTER VALIDATION
- These will secure inter-service communication
- To be implemented after current end-to-end testing validates Phase 1
- Estimated timeline: After Phase 1 stabilization

---

**Document Status:** Phase 1 Complete | Next phases documented | Ready for Phase 2 planning  
**Last Updated:** 2025-12-23zure patterns
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
