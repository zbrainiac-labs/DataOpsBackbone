# E2E Regression Test Plan

> Post-transfer validation for `zbrainiac-labs/DataOpsBackbone` and `zbrainiac-labs/mother-of-all-Projects`
> Date: 2026-04-28

---

## Prerequisites

- [x] Both repos transferred to `zbrainiac-labs` org via GitHub UI
- [x] All containers stopped (`docker compose down`)
- [x] Rotate compromised token from removed runner4 (`ACLQZNOL5SEWPIBL27MKGU3J56XXW`) -- revoked, runner4 deleted
- [x] `.env` updated with `GITHUB_OWNER=zbrainiac-labs` and org runner config
- [x] `SNOW_CONFIG_B64` GitHub secret set on both repos

---

## Phase 1: Infrastructure Startup (DataOpsBackbone)

| Step | Command / Action | Expected Result |
|------|-----------------|-----------------|
| 1.1 | `cd ~/workspace/DataOpsBackbone && ./start.sh` | Docker images build successfully (runner + SonarQube) |
| 1.2 | Wait for SonarQube healthcheck | `http://localhost:9000` returns login page |
| 1.3 | Wait for PostgreSQL healthcheck | `pg_isready` passes in container |
| 1.4 | Verify org runner registers | Runner `runner-org-zbrainiac-labs` appears in GitHub org settings > Actions > Runners |
| 1.5 | Login to SonarQube | `admin` / `ThisIsNotSecure1234!` -- verify quality profiles loaded |
| 1.6 | Verify nginx test history | `http://localhost:8080` serves SQLUnit report page |

---

## Phase 2: Pipeline Execution (mother-of-all-Projects)

| Step | Command / Action | Expected Result |
|------|-----------------|-----------------|
| 2.1 | Push commit to `main` on `zbrainiac-labs/mother-of-all-Projects` | GitHub Actions workflow triggers automatically |
| 2.2 | **Workflow integrity check** | `github-workflow-verification_v1.sh` passes (SHA256 match) |
| 2.3 | **SonarQube scan** | Scan completes, project `mother-of-all-Projects` appears in SonarQube |
| 2.4 | **Quality Gate** | Quality Gate passes (or fails with expected rule violations) |
| 2.5 | **DCM deploy** | `snow dcm deploy` succeeds for `DATAOPS.IOT_RAW_V001.MOTHER_OF_ALL_PROJECTS` |
| 2.6 | **Schema clone** | Zero-copy clone `IOT_RAW_V001_R{N}` created |
| 2.7 | **SQLUnit tests** | All 16 tests pass (0 failures) |
| 2.8 | **Clone cleanup** | Cloned schema dropped |
| 2.9 | **GitHub Release** | Release `v{N}` created with `release.zip` artifact |

---

## Phase 3: SonarQube Rule Validation

Verify all 28 rules produce expected findings from the rule test files.

| Step | Rule Group | Test File | Expected |
|------|-----------|-----------|----------|
| 3.1 | R1-R6 Safety | `workload/rule_test_01_06_safety.sql` | 6 findings (one per bad example) |
| 3.2 | R7 Data Types | `workload/rule_test_07_data_type.sql` | 2 findings (NTZ + LTZ) |
| 3.3 | R8-R13,R26-R28 Naming | `workload/rule_test_08_28_naming.sql` | 8 findings (one per bad name) |
| 3.4 | R14-R15 Dependencies | `workload/rule_test_14_15_dependencies.sql` | 1 finding (cross-schema) |
| 3.5 | R16-R18 Security | `workload/rule_test_16_18_security.sql` | 4 findings |
| 3.6 | R19-R25 Quality+Perf | `workload/rule_test_19_22_data_quality.sql` | 10+ findings |
| 3.7 | R23-R25 Performance | `workload/rule_test_23_25_performance.sql` | 3 findings |
| 3.8 | Negative tests | `sources/definitions/*.sql`, `pre_deploy.sql`, `post_deploy.sql` | Expected findings for FLOAT, naming, USE ROLE, hardcoded prefix |

---

## Phase 4: Snowflake Object Validation

| Step | Validation | SQL |
|------|-----------|-----|
| 4.1 | Database exists | `SHOW DATABASES LIKE 'DATAOPS';` |
| 4.2 | Schema exists | `SHOW SCHEMAS LIKE 'IOT_RAW_V001' IN DATABASE DATAOPS;` |
| 4.3 | DCM project exists | `SHOW DCM PROJECTS IN SCHEMA DATAOPS.IOT_RAW_V001;` |
| 4.4 | Tables deployed | `SELECT COUNT(*) FROM DATAOPS.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'IOT_RAW_V001';` |
| 4.5 | Views deployed | `SELECT COUNT(*) FROM DATAOPS.INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'IOT_RAW_V001';` |
| 4.6 | Dynamic table running | `SHOW DYNAMIC TABLES LIKE 'IOTI_RAW_DT%' IN SCHEMA DATAOPS.IOT_RAW_V001;` |
| 4.7 | Seed data loaded | `SELECT COUNT(*) FROM DATAOPS.IOT_RAW_V001.IOT_RAW;` -- expect 5000 |
| 4.8 | WH recommendations | `SELECT COUNT(*) FROM DATAOPS.IOT_RAW_V001.IOTI_RAW_TB_WH_SIZE_RECOMMENDATION;` -- expect 6 |

---

## Phase 5: Documentation Verification

| Step | Check | Status |
|------|-------|--------|
| 5.1 | All GitHub URLs point to `zbrainiac-labs` in both READMEs | |
| 5.2 | No `zBrainiac` references in tracked files (excluding `.git/`) | |
| 5.3 | `open_points.md` reflects current state | |
| 5.4 | DataOpsBackbone README `.env` example matches actual config structure | |
| 5.5 | Workflow SHA256 hash matches after any workflow changes | |

---

## Phase 6: Cleanup Verification

| Step | Check |
|------|-------|
| 6.1 | No `.DS_Store` files in repo |
| 6.2 | No hardcoded tokens in tracked files |
| 6.3 | `runner1` (per-repo) removed from docker-compose.yml |
| 6.4 | `runner4` (hardcoded token) removed from docker-compose.yml |
| 6.5 | `local-github-process/` directory removed from mother-of-all-Projects |
| 6.6 | Git remotes point to `zbrainiac-labs` in both repos |

---

## Rollback Plan

If the pipeline fails after transfer:
1. Check runner registration in GitHub org settings
2. Verify `SNOW_CONFIG_B64` secret is set on the new org/repo
3. Verify `.env` has correct `GITHUB_ORG=zbrainiac-labs` and `GH_ORG_TOKEN`
4. Re-run `./start.sh` to rebuild containers
5. If SonarQube data is lost, restore from PostgreSQL backup in `./backup/`
