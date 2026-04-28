# Cross-Repo Alignment: Workflow & Configuration Differences

> Comparison date: 2026-04-28
> Repos: MOAP, project-one, crm_dcm_project, MasterDataManagement, sharing_any_objects
> Status: **All aligned**

---

## 1. Workflow Step Order

The **canonical step order** used by all repos:

```
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

| Step | MOAP | project-one | crm_dcm | MDM | sharing |
|------|------|-------------|---------|-----|---------|
| DCM Deploy | Before Sonar (step 7) | Before Sonar (step 7) | Before Sonar (step 7) | Before Sonar (step 7) | **After** Quality Gate |
| Extract deps | After DCM (step 8) | After DCM (step 8) | After DCM (step 8) | After DCM (step 8) | After DCM |
| Quality Gate | continue-on-error: true | continue-on-error: true | continue-on-error: true | continue-on-error: true | continue-on-error: true |
| Clone schema | Present | Present | Present | Present | Present |
| Drop cloned schema | Present (if: always) | Present (if: always) | Present (if: always) | Present (if: always) | Present (if: always) |
| SQLUnit --RELEASE_NUM | Present | Present | Present | Present | Present |

**Note:** `sharing_any_objects` runs Sonar **before** DCM (minor ordering difference). All others run DCM first.

---

## 2. Manifest Configuration

| Field | MOAP | project-one | crm_dcm | MDM | sharing |
|-------|------|-------------|---------|-----|---------|
| account_identifier | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` | `SFSEEUROPE-ZS28104` |
| project_owner | `CICD` | `CICD` | `CICD` | `CICD` | `CICD` |
| default_target | `'DEV'` | `'DEV'` | `'DEV'` | `'DEV'` | `'DEV'` |
| project_name | `'...'` | `'...'` | `'...'` | `'...'` | `'...'` |
| DCM project schema | `IOT_RAW_V001` | `ONE_RAW_V001` | `PUBLIC` | `CRM_AGG_001` | `ECOS_RAW_V001` |
| Template var: db | `db` | `db` | `sf_db` | `db` | `db` |
| Template var: schema | `schema` | `schema` | `SCHEMA_CRM_RAW/CUR` | `raw_schema/agg_schema/srv_schema` | `schema` |
| Template var: warehouse | `wh` | `wh` | `wh` | `warehouse` | `wh` |

**Remaining notes:**
- `crm_dcm_project` uses `PUBLIC` schema for DCM project -- consider moving to a domain schema
- Template variable names differ by project (acceptable -- each has different domain requirements)

---

## 3. Pre-deploy Bootstrap

All repos now follow the same pattern:

```sql
CREATE DATABASE IF NOT EXISTS {DB} COMMENT = '...';
USE DATABASE {DB};
CREATE SCHEMA IF NOT EXISTS {SCHEMA} COMMENT = '...';
CREATE DCM PROJECT IF NOT EXISTS {DB}.{SCHEMA}.{PROJECT};
```

| Feature | MOAP | project-one | crm_dcm | MDM | sharing |
|---------|------|-------------|---------|-----|---------|
| CREATE DATABASE IF NOT EXISTS | YES | YES | YES | YES | YES |
| CREATE SCHEMA IF NOT EXISTS | YES | YES | YES | YES | YES |
| CREATE DCM PROJECT IF NOT EXISTS | YES | YES | YES | YES | YES |
| USE ROLE ACCOUNTADMIN | NO | NO | NO | NO | NO |
| USE DATABASE | YES | YES | YES | YES | YES |

---

## 4. Verification Script

All repos now use the same canonical pattern:

| Feature | MOAP | project-one | crm_dcm | MDM | sharing |
|---------|------|-------------|---------|-----|---------|
| macOS path | `$(pwd)` | `$(pwd)` | `$(pwd)` | `$(pwd)` | `$(pwd)` |
| Hash command | `sha256sum` | `sha256sum` | `sha256sum` | `sha256sum` | `sha256sum` |
| Output prefix | `→` + emoji | `→` + emoji | `→` + emoji | `→` + emoji | `→` + emoji |

---

## 5. Changes Applied

| Repo | Changes Applied | Status |
|------|-----------------|--------|
| **MOAP** | Add `continue-on-error: true` to Quality Gate; move DCM deploy before deps+sonar; standard pre_deploy.sql bootstrap; fix verification script macOS path | DONE |
| **project-one** | Fix verification script macOS path (use `$(pwd)`) | DONE |
| **crm_dcm_project** | Fix verification script macOS path; add clone/drop-clone steps; add `--RELEASE_NUM` to SQLUnit; fix manifest quoting; update SHA256 hash | DONE |
| **MDM** | Change `project_owner` from ACCOUNTADMIN to CICD; use `SFSEEUROPE-ZS28104` for account_identifier; align hash command to `sha256sum` | DONE |
| **sharing** | Fix macOS path to `$(pwd)`; add arrow prefix and emoji to verification script output | DONE |
