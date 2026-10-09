# SQL Linting Rules Reference

82 rules total, split across three engines with **no overlap**.

## Rule Ownership

| Engine | Count | Scope |
|--------|------:|-------|
| SonarQube Text Plugin (`txt:`) | 40 | Regex-based, runs in CI only |
| SonarQube SQL Code Checker (`SQLCC:`) | 19 | AST-based, runs in CI only |
| SQLFluff (external issues) | 23 | AST-based formatting/style, runs locally + CI |

SonarQube rules are created automatically by `sonar-rules-setup.sh` at runner startup.
SQLFluff rules are defined in `sqlfluff/plugins/dataops_rules/__init__.py` and also used by the standalone linter (`sqlfluff/lint.py`).

## DO01-DO28: Custom Regex Rules

These 28 rules exist in both the SonarQube Text Plugin (for CI dashboards) and the SQLFluff plugin (for local linting). The patterns are identical.

| ID | Name | Category | Description |
|----|------|----------|-------------|
| DO01 | safety.create_schema_safe | Safety | CREATE SCHEMA must use IF NOT EXISTS or OR REPLACE |
| DO02 | safety.create_table_safe | Safety | CREATE TABLE must use IF NOT EXISTS or OR REPLACE |
| DO03 | safety.no_hardcoded_prefix | Safety | CREATE must not hardcode database/schema prefix |
| DO04 | security.no_grant_public | Security | GRANT to PUBLIC is not allowed |
| DO05 | safety.drop_if_exists | Safety | DROP must use IF EXISTS |
| DO06 | safety.no_use_statements | Safety | USE DATABASE/SCHEMA/ROLE not allowed |
| DO07 | datatype.timestamp_tz_only | Data Type | Only TIMESTAMP_TZ allowed (no NTZ/LTZ) |
| DO08 | naming.schema_prefix | Naming | Schema names must follow {DOMAIN}_{MATURITY}_ prefix |
| DO09 | naming.schema_version | Naming | Schema names must end with _vNNN version |
| DO10 | naming.table_pattern | Naming | Tables: {DOM}{COMP}_{MAT}_TB_{TEXT} |
| DO11 | naming.view_pattern | Naming | Views: {DOM}{COMP}_{MAT}_VW_{TEXT} |
| DO12 | naming.dynamic_table_pattern | Naming | Dynamic Tables: {DOM}{COMP}_{MAT}_DT_{TEXT} |
| DO13 | naming.stage_pattern | Naming | Stages: {DOM}{COMP}_{MAT}_ST_{TEXT} |
| DO14 | dependency.no_cross_database | Dependency | Cross-database dependencies not allowed |
| DO15 | dependency.no_cross_schema | Dependency | Cross-schema dependencies not allowed |
| DO16 | security.no_grant_all | Security | GRANT ALL PRIVILEGES not allowed |
| DO17 | security.no_accountadmin | Security | ACCOUNTADMIN usage not allowed |
| DO18 | security.no_plaintext_password | Security | Plaintext passwords in DDL not allowed |
| DO19 | quality.no_select_star | Quality | SELECT * not allowed, use explicit columns |
| DO20 | datatype.no_float | Data Type | FLOAT/DOUBLE/REAL not allowed, use NUMBER(p,s) |
| DO21 | datatype.varchar_length | Data Type | VARCHAR must have explicit length |
| DO22 | quality.table_comment | Quality | CREATE TABLE must include COMMENT |
| DO23 | quality.no_order_in_view | Quality | ORDER BY in view definitions not allowed |
| DO24 | quality.copy_on_error | Quality | COPY INTO must include ON_ERROR clause |
| DO25 | quality.dt_target_lag | Quality | Dynamic Tables must specify TARGET_LAG |
| DO26 | naming.file_format_pattern | Naming | File Formats: {DOM}{COMP}_{MAT}_FF_{TEXT} |
| DO27 | naming.procedure_pattern | Naming | Procedures: {DOM}{COMP}_{MAT}_SP_{TEXT} |
| DO28 | naming.task_pattern | Naming | Tasks: {DOM}{COMP}_{MAT}_TK_{TEXT} |

### By category

| Category | Count | Rule IDs |
|----------|------:|----------|
| Safety | 4 | DO01, DO02, DO03, DO05, DO06 |
| Security | 4 | DO04, DO16, DO17, DO18 |
| Naming | 9 | DO08-DO13, DO26, DO27, DO28 |
| Data Type | 3 | DO07, DO20, DO21 |
| Quality | 5 | DO19, DO22, DO23, DO24, DO25 |
| Dependency | 2 | DO14, DO15 |

## SonarQube-Only Rules (not in SQLFluff plugin)

These additional rules are created by `sonar-rules-setup.sh` and run only in the SonarQube Text Plugin. They cover patterns not in DO01-DO28:

- ALTER TABLE DROP COLUMN (CRITICAL)
- TRUNCATE without review (CRITICAL)
- Tasks must be SERVERLESS (no WAREHOUSE keyword)
- Stream naming pattern (_SM_)
- Semantic View naming pattern (_SV_)
- Keywords must be UPPERCASE
- Implicit aliases
- JOIN without ON
- ELSE NULL (unnecessary)
- DEFINE must include COMMENT (DCM)

## SQLFluff Rules (23 AST-based)

These run via the `sqlfluff` CLI and are imported into SonarQube as external issues. They cover formatting and style that regex can't reliably detect:

| Rule | Description | Impact |
|------|-------------|--------|
| LT01-LT14 | Whitespace, indentation, line endings | LOW |
| CP02, CP04 | Identifier and boolean casing | LOW |
| AL01, AL02, AL08 | Alias conventions | LOW |
| AM01, AM03-AM05, AM09 | Ambiguity (ORDER BY, JOIN, SELECT *) | LOW-MEDIUM |
| RF02-RF04 | References and qualification | LOW-MEDIUM |
| ST06, ST07, ST09 | Statement structure | LOW |
| CV06 | Unnecessary ELSE | LOW |

SQLFluff config: `sqlfluff/.sqlfluff` (standalone) or `github-runner/sqlfluff_sonar.cfg` (CI, non-overlapping subset).
