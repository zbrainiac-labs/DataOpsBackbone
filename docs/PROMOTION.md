# Promotion Strategy: DEV to PRD

How code moves from development through validation to production using DataOpsBackbone.

## Environment Model

| Environment | DCM Target | Database Suffix | Purpose |
|-------------|-----------|-----------------|---------|
| DEV | `DEV` | `_DEV` | Feature development, automated CI scans |
| QA | `QA` | `_QA` | Integration testing, manual review |
| PRD | `PRD` | `_PRD` | Production workloads |

Each environment maps to a separate Snowflake database (e.g., `SALES_DEV`, `SALES_QA`, `SALES_PRD`). The schema structure within each database is identical -- DCM ensures consistency.

## Promotion Flow

```
feature branch ──> PR to main ──> merge to main ──> tag release
       │                │               │                │
       │           CI pipeline      deploy DEV       deploy PRD
       │          (scan+validate)                  (with approval)
       ▼                ▼               ▼                ▼
   local dev      quality gate      DEV database    PRD database
```

### 1. Feature Branch (local development)

- Developer works on SQL objects in a consumer repo
- Runs `e2e-test.sh` locally against Docker stack for fast feedback
- SQLFluff + SonarQube scan results visible at `localhost:9000`

### 2. Pull Request (automated validation)

When a PR is opened against `main`, the pipeline runs:

1. **prepare**: Extract dependencies, analyze cross-schema/cross-database refs
2. **scan**: SQLFluff lint + SonarQube scan (quality gate enforced)
3. **deploy**: `snow dcm raw-analyze` + `snow dcm plan --TARGET DEV` (dry-run)
4. **validate**: SQL test execution against cloned schema
5. **cleanup**: Drop test clone schema

The PR is blocked if:
- SonarQube quality gate fails (new issues above threshold)
- DCM plan detects breaking changes
- SQL validation tests fail

### 3. Merge to Main (deploy to DEV)

On merge, the pipeline runs again with:

```yaml
snow dcm deploy --TARGET DEV --ALIAS "main-$(git rev-parse --short HEAD)"
```

The `--ALIAS` links the deployment to the specific commit for traceability.

### 4. Tag Release (deploy to PRD)

Create a release tag to trigger production deployment:

```bash
git tag -a v1.2.3 -m "Release: add customer dimension tables"
git push origin v1.2.3
```

The release pipeline runs:

```yaml
snow dcm deploy --TARGET PRD --ALIAS "v1.2.3"
```

## Approval Gates

### GitHub Environment Protection Rules

Configure environment protection in GitHub repo Settings > Environments:

| Environment | Required Reviewers | Wait Timer | Branch Policy |
|-------------|-------------------|------------|---------------|
| DEV | None (auto-deploy) | None | `main` only |
| QA | 1 reviewer | None | `main` only |
| PRD | 2 reviewers | 30 min | tags `v*` only |

### DCM Target Configuration

In the consumer repo's `snowflake.yml`:

```yaml
dcm:
  targets:
    DEV:
      database: SALES_DEV
      warehouse: DEV_WH
    QA:
      database: SALES_QA
      warehouse: QA_WH
    PRD:
      database: SALES_PRD
      warehouse: PRD_WH
```

## Rollback

### Option 1: Revert Commit

```bash
git revert <commit-hash>
git push origin main
```

This triggers a new DEV deployment that undoes the change. DCM handles object drops/recreates.

### Option 2: DCM Alias Traceability

Every deployment is tagged with a `--ALIAS` (commit hash or version tag). To identify what was deployed:

```bash
snow dcm list --TARGET PRD
```

Find the previous good alias and redeploy from that commit:

```bash
git checkout v1.1.0
snow dcm deploy --TARGET PRD --ALIAS "rollback-v1.1.0"
```

### Option 3: Schema Clone Rollback

For data-preserving rollback, clone the schema before deploying:

```sql
CREATE SCHEMA SALES_PRD.BACKUP_BEFORE_V123 CLONE SALES_PRD.MAIN_V001;
```

Then swap back if needed.

## Git Tags and DCM Aliases

| Git Artifact | DCM Alias | Example |
|-------------|-----------|---------|
| PR branch | `pr-<number>` | `pr-42` |
| Main merge | `main-<short-hash>` | `main-a1b2c3d` |
| Release tag | `v<semver>` | `v1.2.3` |
| Hotfix | `hotfix-<ticket>` | `hotfix-JIRA-456` |

The alias provides full traceability from a Snowflake object back to the exact source code version that created it.
