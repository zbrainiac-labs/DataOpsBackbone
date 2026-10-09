# Quickstart: Your First DataOps Pipeline in 15 Minutes

## Prerequisites

- Docker Desktop (with Docker Compose v2+)
- GitHub CLI (`gh`) authenticated
- A Snowflake account with ACCOUNTADMIN access
- A GitHub org (or personal account) with Actions enabled

## Step 1: Clone and Configure (3 min)

```bash
git clone https://github.com/zbrainiac-labs/DataOpsBackbone.git
cd DataOpsBackbone
cp .env.example .env
```

Edit `.env` with your values:

```dotenv
GH_RUNNER_TOKEN=<your GitHub PAT with repo scope>
GITHUB_OWNER=<your-github-user>
GITHUB_ORG=<your-github-org>
GH_ORG_TOKEN=<classic PAT with admin:org scope>

POSTGRES_USER=sonar
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=sonarqube
SONAR_JDBC_USERNAME=sonar
SONAR_JDBC_PASSWORD=<strong-password>
SONAR_ADMIN_PASS=<strong-password>

CONNECTION_NAME=<your-connection>
SNOW_ACCOUNT=<your-account.region>
SNOW_USER=SVC_CICD
SNOW_ROLE=CICD
SNOW_DATABASE=OPS_DEV
SNOW_SCHEMA=OPS_RAW_V001
SNOW_WAREHOUSE=MD_TEST_WH
SNOW_PAT=<your-programmatic-access-token>
```

## Step 2: Create Snowflake Service User (2 min)

```sql
USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS CICD;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE CICD;
GRANT CREATE ROLE ON ACCOUNT TO ROLE CICD;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE CICD;
GRANT MANAGE WAREHOUSES ON ACCOUNT TO ROLE CICD;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE CICD;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE CICD;

CREATE USER IF NOT EXISTS SVC_CICD
  TYPE = SERVICE
  DEFAULT_ROLE = CICD
  DEFAULT_WAREHOUSE = MD_TEST_WH
  COMMENT = 'Service user for CI/CD pipeline';
GRANT ROLE CICD TO USER SVC_CICD;

ALTER USER SVC_CICD ADD PROGRAMMATIC ACCESS TOKEN CICD_PAT
  ROLE_RESTRICTION = CICD
  DAYS_TO_EXPIRY = 365;
-- Copy the token into .env as SNOW_PAT
```

## Step 3: Start the Stack (3 min)

```bash
./start.sh
```

This builds Docker images (runner + SonarQube) and starts all services. Wait ~2 minutes for SonarQube to become healthy.

Verify:
- SonarQube: http://localhost:9000
- Test Reports: http://localhost:8080

## Step 4: Fork a Consumer Repo (2 min)

```bash
gh repo fork zbrainiac-labs/mother-of-all-Projects --clone
cd mother-of-all-Projects
```

Update `.github/workflows/update-local-repo.yml` with your database/schema names:

```yaml
permissions:
  id-token: write
  contents: write
  actions: read
  checks: write

jobs:
  pipeline:
    uses: YOUR_ORG/DataOpsBackbone/.github/workflows/dataops-pipeline.yml@main
    with:
      SOURCE_DATABASE: OPS_DEV
      SOURCE_SCHEMA: OPS_RAW_v001
      DCM_PROJECT_IDENTIFIER: OPS_DEV.OPS_DCM.MOTHER_OF_ALL_PROJECTS
      DCM_TARGET: DEV
      CLONE_PER_BUILD: true
    secrets: inherit
```

## Step 5: Push and Watch (5 min)

```bash
git add -A && git commit -m "initial pipeline setup" && git push
```

Open GitHub Actions to see the 6-job pipeline:

1. **prepare** - validates inputs, runs pre_deploy.sql
2. **scan** - SQLFluff + SonarQube + Quality Gate
3. **deploy** - DCM deploy to Snowflake
4. **validate** - SQL tests (CTRF)
5. **cleanup** - drops clone schema
6. **release** - GitHub Release + Step Summary

## Step 6: Check Results

- **SonarQube**: http://localhost:9000 - see issues, quality gate status
- **Test Reports**: http://localhost:8080 - SQL test history
- **GitHub Step Summary**: click the Actions run for deployment summary + timing

## Next Steps

- Add your own SQL files to `sources/`
- Add SQL tests to `sqlunit/tests.sqltest`
- Enable Quality Gate enforcement: `QUALITY_GATE_ENFORCED: true`
- Set up OIDC for secretless auth (see main README)
