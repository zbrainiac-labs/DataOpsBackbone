# Cross-Repo Alignment: Workflow & Configuration Differences

> Comparison date: 2026-04-28
> Repos: MOAP, project-one, crm_dcm_project, MasterDataManagement, sharing_any_objects

---

## 1. Workflow Step Order Differences

The **canonical step order** (used by `project-one`, `MasterDataManagement`, `sharing_any_objects`) is:

```
1. Set up dynamic base directories
2. Show repo info
3. Checkout repository
4. Pull latest changes
5. Set up github runner env
6. GitHub Actions workflow validates
7. DCM Analyze + Plan + Deploy          <-- DCM FIRST
8. Extract dependencies                 <-- deps AFTER deploy
9. Run Sonar Scanner
10. Wait for Quality Gate (continue-on-error: true)
11. Clone schema for regression tests
12. Run SQL Validation Tests
13. Drop cloned schema (if: always)
14. Zip source files
15. Create GitHub Release
```

| Step | MOAP | project-one | crm_dcm | MDM | sharing |
|------|------|-------------|---------|-----|---------|
| Extract deps | **Before** Sonar (step 7) | After DCM (step 8) | After DCM (step 8) | After DCM (step 8) | After DCM (step 7) |
| Sonar Scanner | Step 8 | Step 9 | Step 9 | Step 9 | Step 8 |
| Quality Gate | **No continue-on-error** | continue-on-error: true | continue-on-error: true | continue-on-error: true | continue-on-error: true |
| DCM Deploy | After Quality Gate | **Before** Sonar | **Before** Sonar+deps | **Before** Sonar | **Before** Sonar |
| Clone schema | Present | Present | **MISSING** | Present | Present |
| Drop cloned schema | Present (if: always) | Present (if: always) | **MISSING** | Present (if: always) | Present (if: always) |
| SQLUnit --RELEASE_NUM | Present | Present | **MISSING** | Present | Present |

### Summary: MOAP is the outlier

- **MOAP runs deps+sonar BEFORE DCM deploy** (others do DCM first, then deps+sonar)
- **MOAP is the only repo WITHOUT `continue-on-error: true`** on Quality Gate -- this is why the pipeline blocks
- **crm_dcm_project is missing** clone/drop-clone steps and `--RELEASE_NUM` in SQLUnit

---

## 2. Manifest Differences

| Field | MOAP | project-one | crm_dcm | MDM | sharing |
|-------|------|-------------|---------|-----|---------|
| account_identifier | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` | **`ZS28104`** (short form) | `SFSEEUROPE-ZS28104` |
| project_owner | `CICD` | `CICD` | `CICD` | **`ACCOUNTADMIN`** | `CICD` |
| default_target quotes | `'DEV'` | `'DEV'` | `DEV` (no quotes) | `'DEV'` | `'DEV'` |
| project_name quotes | `'...'` | `'...'` | No quotes | `'...'` | `'...'` |
| DCM project schema | `IOT_RAW_V001` | `ONE_RAW_V001` | **`PUBLIC`** | `CRM_AGG_001` | `ECOS_RAW_V001` |
| Template var: db | `db` | `db` | `sf_db` | `db` | `db` |
| Template var: schema | `schema` | `schema` | `SCHEMA_CRM_RAW/CUR` | `raw_schema/agg_schema/srv_schema` | `schema` |
| Template var: warehouse | `wh` | `wh` | `wh` | `warehouse` | `wh` |

### Issues:
- **MDM uses `ACCOUNTADMIN` as project_owner** -- should be `CICD`
- **MDM uses short `ZS28104`** -- others use `SFSEEUROPE-ZS28104`
- **crm_dcm_project uses `PUBLIC` schema** for DCM project -- should be a domain schema
- **crm_dcm_project uses inconsistent quoting** (no quotes on `DEV`, project_name)
- **Template variable names are inconsistent** across repos (`db`/`sf_db`, `schema`/`SCHEMA_CRM_RAW`, `wh`/`warehouse`)

---

## 3. Pre-deploy Differences

| Feature | MOAP | project-one | crm_dcm | MDM | sharing |
|---------|------|-------------|---------|-----|---------|
| CREATE DATABASE IF NOT EXISTS | **NO** (no DB create) | YES | YES | YES | YES |
| CREATE SCHEMA IF NOT EXISTS | **NO** (no schema create) | YES | YES | YES | YES |
| CREATE DCM PROJECT IF NOT EXISTS | **NO** | YES | YES | YES | YES |
| USE ROLE ACCOUNTADMIN | **YES** | NO | NO | NO | NO |
| Resource Monitor creation | **YES** | NO | NO | NO | NO |
| USE DA
TABASE | NO | YES | YES | YES | YES |

### Issues:
- **MOAP pre_deploy.sql is fundamentally different** -- it creates a resource monitor with `USE ROLE ACCOUNTADMIN` instead of bootstrapping DB/schema/DCM project
- **MOAP is missing the standard bootstrap pattern** (CREATE DATABASE/SCHEMA/DCM PROJECT)
- All other repos follow the same pattern: CREATE DB -> USE DB -> CREATE SCHEMA(s) -> CREATE DCM PROJECT

---

## 4. Verification Script Differences

| Feature | MOAP | project-one | crm_dcm | MDM | sharing |
|---------|------|-------------|---------|-----|---------|
| macOS path | `mother-of-all-Projects` | **`mother-of-all-Projects`** (wrong!) | **`mother-of-all-Projects`** (wrong!) | `$(pwd)` (correct) | `sharing_any_objects` (correct) |
| Hash command | `sha256sum` | `sha256sum` | `sha256sum` | **`shasum -a 256`** (macOS native) | `sha256sum` |
| Output prefix | `→ Expected` / `→ Actual` | `→ Expected` / `→ Actual` | `→ Expected` / `→ Actual` | `→ Expected` / `→ Actual` | `Expected` / `Actual` (no arrow) |
| Emoji in output | YES | YES | YES | YES | **NO** |

### Issues:
- **project-one and crm_dcm_project hardcode `mother-of-all-Projects`** in their macOS path -- these will fail on macOS dev
- **MDM uses `shasum -a 256`** instead of `sha256sum` -- correct for macOS but different from others
- **sharing_any_objects** has slightly different output formatting (no arrows, no emoji)
- Ideally all should use `$(pwd)` like MDM or `$PROJECT_KEY` for portability

---

## 5. Recommended Canonical Template

Based on the majority pattern (project-one, MDM, sharing), the **canonical workflow** should be:

```yaml
# Step order:
1. Set up dynamic base directories
2. Show repo info  
3. Checkout repository
4. Pull latest changes
5. Set up github runner env
6. GitHub Actions workflow validates
7. DCM Analyze + Plan + Deploy
8. Extract dependencies
9. Run Sonar Scanner
10. Wait for Quality Gate (continue-on-error: true)
11. Clone schema for regression tests
12. Run SQL Validation Tests (with --RELEASE_NUM)
13. Drop cloned schema (if: always)
14. Zip source files
15. Create GitHub Release
```

### Changes needed per repo:

| Repo | Changes Required | Status |
|------|-----------------|--------|
| **MOAP** | Add `continue-on-error: true` to Quality Gate; move DCM deploy before deps+sonar; standard pre_deploy.sql bootstrap; fix verification script macOS path | DONE |
| **project-one** | Fix verification script macOS path (use `$(pwd)`) | DONE |
| **crm_dcm_project** | Fix verification script macOS path; add clone/drop-clone steps; add `--RELEASE_NUM` to SQLUnit; fix manifest quoting; update SHA256 hash | DONE |
| **MDM** | Change `project_owner` from ACCOUNTADMIN to CICD; use `SFSEEUROPE-ZS28104` for account_identifier; align hash command to `sha256sum` | DONE |
| **sharing** | Fix macOS path to `$(pwd)`; add arrow prefix and emoji to verification script output | DONE |
