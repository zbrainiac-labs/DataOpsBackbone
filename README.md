# **DataOps Unchained: Infrastructure that Scales**

[![Update Local Repository and Run Sonar Scanner](https://github.com/zBrainiac/mother-of-all-Projects/actions/workflows/update-local-repo.yml/badge.svg)](https://github.com/zBrainiac/mother-of-all-Projects/actions/workflows/update-local-repo.yml)
[![Docker Build and Push to Docker Hub (Multi-Arch)](https://github.com/zBrainiac/sql_quality_check/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/zBrainiac/sql_quality_check/actions/workflows/docker-publish.yml)

> **A hands-on reference architecture for fully automated SQL code quality pipelines using SonarQube, GitHub Actions, and Snowflake.**

---

## Why / What / How

### Why?
#### In large, federated organizations, scaling analytics isn’t (just) a tech challenge — it’s an operational one.

From a technological and operational perspective, automation, governance and consistency are vital for scaling analytics in large, federated organisations. With agile methodology and modularisation, deployment volume can rise to hundreds or thousands per day, so manual QA simply cannot keep pace. For example, if 15 analytics teams were to deploy changes daily, the number of full-time reviewers required for manual reviews would be prohibitively high, resulting in bottlenecks, missed checks and an increased risk of inconsistent standards and data incidents.
DataOpsBackbone addresses these issues by automating every critical step:

**Quality Gates** leverage **SonarQube** code scans to enforce SQL and customisable coding rules based on regular expressions, which are applied automatically with every git push request. For example, forgetting to prefix a schema name or hardcoding a database name triggers an automated block and feedback, thereby enforcing standards before code can be shipped.
- Releases are versioned and deployed via DCM (Database Change Management) with plan/deploy semantics, then validated through SQL tests. This keeps production safe from changes that have not been properly tested.
- Governance is built in: rules such as 'no grants to PUBLIC' or 'only UTC TIMESTAMP allowed' are continuously enforced, and all compliance-relevant data (such as SQL code scans and test results) is logged for auditing purposes.
- Teams have full transparency and can be agile and reduce technical debt themselves. Automation enforces rules and monitors testing over time, so centralised approvals no longer become a bottleneck.

This setup offers repeatability, auditability and peace of mind, enabling new teams to get up and running quickly and allowing developers to focus on creating value rather than policing standards. The showcased projects are practical blueprints for achieving reliable, scalable analytics operations with Snowflake and GitHub Actions, not just demos.


This showcase project, together with [**Mother-of-all-Projects**](https://github.com/zBrainiac/mother-of-all-Projects) — demonstrates a fully automated DataOps setup designed to enforce SQL code quality, structure release flows, and scale confidently with Snowflake and GitHub Actions.

---

### What?

A DataOps pipeline that automates:

- Syncing changes from GitHub
- SQL linting & validation (SonarQube + regex rules)
- Declarative schema deployment via Snowflake DCM (Database Change Management)
- SQL validation testing against deployed objects
- Packaging deployable artifacts

#### Overview of the infrastructure:
![overview infrastructure](images/DataOps_infra_overview.png)

---

### How?

It combines:

- **GitHub Actions** (with custom self-hosted runners)
- **SonarQube** extended with SQL & Text plugins
- **Docker Compose** for local stack orchestration
- **Snowflake CLI** with DCM for declarative deployment (`DEFINE` syntax + Jinja templating)
- **SQLUnit** for automated SQL testing

---

## Project Structure

- **[mother-of-all-Projects](https://github.com/zBrainiac/mother-of-all-Projects)**  
  GitHub workflows, SQL refactoring logic, Snowflake deployment scripts, and validation via SQLUnit.

- **[DataOps Backbone](https://github.com/zBrainiac/DataOpsBackbone)**  
  Dockerized infrastructure stack for:
  - SonarQube + PostgreSQL
  - GitHub self-hosted runners
  - Local development/testing

---
## Architecture Overview - Data objects

The showcase is built around two distinct data domains, each represented as an individual database within the same Snowflake account. This approach allows for logical isolation and independent management of domain-specific data assets.

Within each domain (database), schemas are strategically utilized to achieve two key objectives:
* **Maturity Levels:** Schemas separate data objects based on their maturity level (e.g., raw, curated, conformed). This provides a clear path for data as it progresses through various transformation stages.
* **Versioning:** Schemas also incorporate versioning for underlying database objects like tables, views, stages and procedures. This ensures traceability, facilitates rollbacks, and supports agile development by allowing iterative changes without disrupting existing consumers.

### Why This Approach?
1. **Improved Organization:** Data assets are logically grouped by business domain, making them easier to discover and manage.
2. **Enhanced Data Governance:** Clear maturity levels and versioning promote better control over data quality and evolution.
3. **Scalability & Maintainability:** The modular design reduces interdependencies, simplifying development, testing, and maintenance.
4. **Demonstrates Best Practices:** Provides a practical example of implementing a domain-driven data architecture in Snowflake.

![DataOps_SF_object_structure.png](images/DataOps_SF_object_structure.png)


### Drive modularization for better Resilience

We not only use static source code analysis to review new code coming into the environment, but also check the existing setup and enforce isolation more effectively.
By isolating domains and versions, the impact of changes or failures in one area on others is minimised, thereby enhancing overall system stability and aiding regression testing.

![DataOps_SF_dep_rules.png](images/DataOps_SF_dep_rules.png)
---

## Naming Convention

All Snowflake object names use **UPPERCASE** with underscore separators.

### Database: `{DOMAIN}_{ENV}`

| Position | Field | Values |
|----------|-------|--------|
| 1-3 | Domain | 3-char business domain (`IOT`, `CLR`, `PAY`, `CRM`, `REF`) |
| 4-7 | Environment | `_DEV`, `_TE1`, `_PER`, `_PRD` |

Examples: `CLR_DEV`, `PAY_PRD`, `IOT_TE1`

### Schema: `{DOMAIN}_{MATURITY}_v{NNN}`

| Position | Field | Values |
|----------|-------|--------|
| 1-3 | Domain | Same 3-char domain code |
| 4-8 | Maturity | `_RAW_`, `_CUR_`, `_AGG_`, `_GOL_` |
| 9-12 | Version | `v001` -- `v999` |

Examples: `CLR_RAW_v001`, `IOT_AGG_v012`, `REF_CUR_v003`

### Database Objects (tables, views, stages, tasks, etc.): `{DOMAIN}{COMP}_{MATURITY}_{TYPE}_{TEXT}`

| Position | Field | Description | Values |
|----------|-------|-------------|--------|
| 1-3 | Domain | 3-char business domain | `IOT`, `CLR`, `PAY`, `CRM`, `REF` |
| 4 | Component | Sub-component (GitHub repo) | Single char: `I`, `A`, `T`, `P`, etc. |
| 5-8 | Maturity | Data maturity level | `_RAW`, `_CUR`, `_AGG`, `_GOL` |
| 9-12 | Object type | Snowflake object type | `_TB_`, `_VW_`, `_DT_`, `_ST_`, `_FF_`, `_SP_`, `_TK_` |
| 13+ | Free text | Business-meaningful name | Uppercase, underscores allowed |

Examples:
- `ICGI_RAW_TB_SWIFT_MESSAGES` -- ICG domain, Ingestion repo, raw table
- `ICGA_AGG_DT_SWIFT_PACS008` -- ICG domain, Aggregation repo, aggregated dynamic table
- `IOTI_RAW_VW_SENSOR_GEOLOC` -- IOT domain, Ingestion repo, raw view
- `ICGI_RAW_ST_SWIFT_INBOUND` -- ICG domain, Ingestion repo, raw stage
- `ICGI_RAW_FF_XML` -- ICG domain, Ingestion repo, raw file format

---
## SQL Linting Rules and Regex Patterns
This list provides a few examples of SQL validation rules, each of which is paired with a regular expression (regex) that can be used to identify non-compliant code using the Community Text plugin of SonarQube.

Backups of these rules, which can be restored as a Quality Profile, are available in the repository ([link](backup/2026-04-27_quality_profiles_text_plugin.xml)). Rules are also auto-created at runner startup via `sonar-rules-setup.sh`.

### Safety Rules

#### 1. Disallow `CREATE SCHEMA` without `IF NOT EXISTS` or `REPLACE`
```regex
(?i)^\s*CREATE\s+(?!OR\s+REPLACE\b)(?!.*\bIF\s+NOT\s+EXISTS\b).*?\bSCHEMA\b
```

#### 2. Disallow CREATE TABLE without IF NOT EXISTS or REPLACE
```regex
(?is)^(?!\s*--).*CREATE\s+(?!OR\s+REPLACE\b|.*IF\s+NOT\s+EXISTS\b).*TABLE\b
```

#### 3. Disallow CREATE statements with hardcoded database and/or schema prefix
```regex
(?i)^(?!\s*--)\s*create\s+(or\s+replace\s+)?(table|view|schema)\s+(if\s+not\s+exists\s+)?[a-z0-9_]+\.[a-z0-9_]+(\.[a-z0-9_]+)?
```

#### 4. Disallow GRANT statements to PUBLIC
```regex
(?i)^(?!\s*--).*grant\s+.*\s+to\s+public\b
```

#### 5. Disallow dropping objects without IF EXISTS
```regex
(?i)^\s*DROP\s+(SCHEMA|TABLE|VIEW|DYNAMIC\s+TABLE|STAGE|FILE\s+FORMAT|PROCEDURE|FUNCTION|TASK)\s+(?!IF\s+EXISTS\b)
```

#### 6. Disallow hardcoded USE DATABASE, USE SCHEMA, or USE ROLE statements
```regex
(?i)^(?!\s*--)\s*USE\s+(DATABASE|SCHEMA|ROLE)\b
```

### Data Type Rules

#### 7. Disallow TIMESTAMP_NTZ and TIMESTAMP_LTZ (only TIMESTAMP_TZ allowed)
```regex
(?i)(?<!--.*)\bTIMESTAMP_(NTZ|LTZ)(\s*\(\s*\d+\s*\))?\b
```

### Naming Convention Rules

#### 8. Schema names must follow `{DOMAIN}_{MATURITY}_` prefix pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?(?!RAW_|CUR_|AGG_|GOL_|REF_)[a-z0-9_]+;
```

#### 9. Schema names must end with version pattern `_vNNN`
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?[a-z0-9_]+(?<!_v\d{3});
```

#### 10. Table names must follow `{DOM}{COMP}_{MAT}_{TB}_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TB_)[A-Z_][A-Z0-9_]*
```

#### 11. View names must follow `{DOM}{COMP}_{MAT}_{VW}_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_VW_)[A-Z_][A-Z0-9_]*
```

#### 12. Dynamic Table names must follow `{DOM}{COMP}_{MAT}_{DT}_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_DT_)[A-Z_][A-Z0-9_]*
```

#### 13. Stage names must follow `{DOM}{COMP}_{MAT}_{ST}_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?STAGE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_ST_)[A-Z_][A-Z0-9_]*
```

### Dependency Rules

#### 14. Disallow Cross-Database Dependencies
```regex
^.*cross_db_true.*$
```

#### 15. Disallow Cross-Schema Dependencies
```regex
^.*cross_schema_true.*$
```

### Security & Access Control Rules

#### 16. Disallow GRANT ALL PRIVILEGES
```regex
(?i)^(?!\s*--)\s*GRANT\s+ALL\s+(PRIVILEGES\s+)?ON\b
```

#### 17. Disallow ACCOUNTADMIN usage in SQL scripts
```regex
(?i)^(?!\s*--)\s*(USE\s+ROLE|SET\s+ROLE|GRANT\s+.*TO\s+ROLE|GRANT\s+ROLE)\s+.*\bACCOUNTADMIN\b
```

#### 18. Disallow plaintext passwords in DDL
```regex
(?i)^(?!\s*--)\s*.*PASSWORD\s*=\s*'[^']+'
```

### Data Quality & Consistency Rules

#### 19. Disallow SELECT * (force explicit column lists)
```regex
(?i)^(?!\s*--)\s*SELECT\s+\*\s+FROM\b
```

#### 20. Disallow FLOAT/DOUBLE -- prefer NUMBER(p,s)
```regex
(?i)(?<!--.*)\b(FLOAT|DOUBLE|REAL)\b
```

#### 21. Disallow VARCHAR without explicit length
```regex
(?i)(?<!--.*)\bVARCHAR\s*[^(]
```

#### 22. CREATE TABLE must include COMMENT
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TABLE\s+(?!.*\bCOMMENT\b).*;\s*$
```

### Performance & Best Practice Rules

#### 23. Disallow ORDER BY in view definitions
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\b[\s\S]*?\bORDER\s+BY\b
```

#### 24. Disallow COPY INTO without ON_ERROR clause
```regex
(?i)^(?!\s*--)\s*COPY\s+INTO\s+(?!.*\bON_ERROR\b).*;\s*$
```

#### 25. Dynamic Tables must specify TARGET_LAG
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?!.*\bTARGET_LAG\b)
```

### Naming Convention Rules (additional object types)

#### 26. File Format names must follow `{DOM}{COMP}_{MAT}_FF_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?FILE\s+FORMAT\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_FF_)[A-Z_][A-Z0-9_]*
```

#### 27. Stored Procedure names must follow `{DOM}{COMP}_{MAT}_SP_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_SP_)[A-Z_][A-Z0-9_]*
```

#### 28. Task names must follow `{DOM}{COMP}_{MAT}_TK_` pattern
```regex
(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TASK\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TK_)[A-Z_][A-Z0-9_]*
```

## Monitoring
### Issue overview
![Issue overview](images/sq_rules.png)

### Issue within code
![Issue within code](images/sq_Issue_within_code.png)

### Technical debt
![Technical debt](images/sq_technical_dept.png)


### Monitor the history of test case execution
![unitth_overview.png](images/unitth_overview.png)

## Quick Setup Guide


### Step 1: Create all Snowflake objects
The [DataOps_init.sql](DataOps_init.sql) script creates all required database objects, including users and roles.
Simply log in to your Snowflake account and create all your objects at once.


### Step 2: Generate a PAT for the service user

```SQL
ALTER USER IF EXISTS SVC_CICD ADD PROGRAMMATIC ACCESS TOKEN CICD_PAT
  ROLE_RESTRICTION = CICD
  DAYS_TO_EXPIRY = 365
  COMMENT = 'CI/CD pipeline PAT';
-- copy <your token>
```

### Step 3: Configure `.env` (single source of truth)

All configuration lives in one file. `start.sh` auto-generates `SNOW_CONFIG_B64` and the runner auto-generates `SONAR_TOKEN` at startup.

```dotenv
# GitHub
GH_RUNNER_TOKEN=<...>
GITHUB_OWNER=<your GitHub org/user>
GITHUB_REPO_1=<your project>

# SonarQube (SONAR_TOKEN is auto-generated at runner startup)
POSTGRES_USER=sonar
POSTGRES_PASSWORD=sonar
POSTGRES_DB=sonarqube
SONAR_JDBC_USERNAME=sonar
SONAR_JDBC_PASSWORD=sonar
SONAR_ADMIN_PASS=ThisIsNotSecure1234!

# Snowflake (SNOW_CONFIG_B64 is auto-generated by start.sh)
CONNECTION_NAME=<your-connection-name>
SNOW_ACCOUNT=<your-account>
SNOW_USER=SVC_CICD
SNOW_ROLE=CICD
SNOW_DATABASE=DATAOPS
SNOW_SCHEMA=IOT_RAW_V001
SNOW_WAREHOUSE=MD_TEST_WH
SNOW_PAT=<your PAT from Step 2>
```

---
### Step 4: Upload GitHub Secret

Only **one** secret is needed:

```bash
./start.sh  # generates SNOW_CONFIG_B64 automatically
gh secret set SNOW_CONFIG_B64 --repo <owner>/<repo> < SNOW_CONFIG_B64
```

`SONAR_TOKEN` and `SNOW_CONNECTION_NAME` secrets are **no longer needed** -- they are auto-generated at runtime.

---

### Step 5: Run It

1. Start your local stack via `./start.sh`
2. Access SonarQube at: [http://localhost:9000](http://localhost:9000)  
  **Login**: `admin` / `ThisIsNotSecure1234!` (default 'admin')
3. Trigger your GitHub workflow
4. Check results in sonarqube
5. monitor SQLUnit test results (incl. history) at: [http://localhost:8080](http://localhost:8080)

---

## Final Thoughts

This is not just a demo. It's a **reusable framework** to scale DataOps -- combining validation, governance, and automation into one consistent, testable workflow.
