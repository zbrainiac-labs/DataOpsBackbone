# SQLFluff — Alternative SQL Linting Implementation

This folder provides the same 28 SQL linting rules from SonarQube implemented using **SQLFluff** (Python-based SQL linter) as an alternative to the SonarQube + Text Plugin approach.

## Why?

| | SonarQube | SQLFluff |
|---|-----------|----------|
| **Setup** | Server + PostgreSQL + runner | `pip install sqlfluff` |
| **Execution** | CI/CD pipeline via scanner | CLI or pre-commit hook |
| **Custom rules** | Regex via Text Plugin | Python plugin + regex |
| **Snowflake dialect** | Text-only (no AST) | Full AST parsing |
| **Auto-fix** | No | Yes (formatting) |
| **Report format** | SonarQube dashboard | Text, JSON, CTRF |

## Quick Start

```bash
pip install sqlfluff
cd sqlfluff/
python3 lint.py test_sql/
python3 lint.py test_sql/ --format=json
```

## Structure

```
sqlfluff/
├── .sqlfluff                          # SQLFluff config (Snowflake dialect, UPPER keywords)
├── lint.py                            # Combined runner: SQLFluff + custom rules
├── plugins/
│   └── dataops_rules/
│       └── __init__.py                # 28 custom regex rules (DO01–DO28)
├── test_sql/
│   ├── good_example.sql               # Compliant SQL (0 violations expected)
│   └── bad_example.sql                # Non-compliant SQL (many violations expected)
└── README.md
```

## Rules Mapping (SonarQube → SQLFluff)

| # | Code | Category | Rule |
|---|------|----------|------|
| 1 | DO01 | Safety | CREATE SCHEMA must use IF NOT EXISTS or OR REPLACE |
| 2 | DO02 | Safety | CREATE TABLE must use IF NOT EXISTS or OR REPLACE |
| 3 | DO03 | Safety | No hardcoded database/schema prefix |
| 4 | DO04 | Security | No GRANT to PUBLIC |
| 5 | DO05 | Safety | DROP must use IF EXISTS |
| 6 | DO06 | Safety | No USE DATABASE/SCHEMA/ROLE |
| 7 | DO07 | Data Type | Only TIMESTAMP_TZ (no NTZ/LTZ) |
| 8 | DO08 | Naming | Schema prefix pattern |
| 9 | DO09 | Naming | Schema version _vNNN |
| 10 | DO10 | Naming | Table naming {DOM}{COMP}_{MAT}_{TB}_ |
| 11 | DO11 | Naming | View naming {DOM}{COMP}_{MAT}_{VW}_ |
| 12 | DO12 | Naming | Dynamic Table naming {DOM}{COMP}_{MAT}_{DT}_ |
| 13 | DO13 | Naming | Stage naming {DOM}{COMP}_{MAT}_{ST}_ |
| 14 | DO14 | Dependency | No cross-database dependencies |
| 15 | DO15 | Dependency | No cross-schema dependencies |
| 16 | DO16 | Security | No GRANT ALL PRIVILEGES |
| 17 | DO17 | Security | No ACCOUNTADMIN usage |
| 18 | DO18 | Security | No plaintext passwords |
| 19 | DO19 | Quality | No SELECT * |
| 20 | DO20 | Data Type | No FLOAT/DOUBLE/REAL |
| 21 | DO21 | Data Type | VARCHAR must have explicit length |
| 22 | DO22 | Quality | CREATE TABLE must include COMMENT |
| 23 | DO23 | Quality | No ORDER BY in views |
| 24 | DO24 | Quality | COPY INTO must have ON_ERROR |
| 25 | DO25 | Quality | Dynamic Tables must specify TARGET_LAG |
| 26 | DO26 | Naming | File Format naming {DOM}{COMP}_{MAT}_FF_ |
| 27 | DO27 | Naming | Stored Procedure naming {DOM}{COMP}_{MAT}_SP_ |
| 28 | DO28 | Naming | Task naming {DOM}{COMP}_{MAT}_TK_ |

## Output Formats

**Text** (default):
```
======================================================================
 DataOps SQL Linter Results
======================================================================
--- DataOps custom rules violations (5) ---
  test_sql/bad_example.sql:6  [DO01] CREATE SCHEMA must use IF NOT EXISTS or OR REPLACE.
  test_sql/bad_example.sql:9  [DO02] CREATE TABLE must use IF NOT EXISTS or OR REPLACE.
  ...
```

**CTRF JSON** (`--format=json`):
Writes `lint_report.json` in CTRF format, compatible with UnitTestHistory.
