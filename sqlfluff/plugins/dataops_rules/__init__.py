"""DataOps custom rules for SQLFluff — mirrors SonarQube regex rules."""

from sqlfluff.core.plugin import hookimpl
from sqlfluff.core.rules import BaseRule, LintResult, RuleGhost
import regex as re


RULES = [
    {
        "code": "DO01",
        "name": "safety.create_schema_safe",
        "description": "CREATE SCHEMA must use IF NOT EXISTS or OR REPLACE.",
        "pattern": r"(?i)^\s*CREATE\s+(?!OR\s+REPLACE\b)(?!.*\bIF\s+NOT\s+EXISTS\b).*?\bSCHEMA\b",
        "category": "Safety",
    },
    {
        "code": "DO02",
        "name": "safety.create_table_safe",
        "description": "CREATE TABLE must use IF NOT EXISTS or OR REPLACE.",
        "pattern": r"(?is)^(?!\s*--).*CREATE\s+(?!OR\s+REPLACE\b|.*IF\s+NOT\s+EXISTS\b).*TABLE\b",
        "category": "Safety",
    },
    {
        "code": "DO03",
        "name": "safety.no_hardcoded_prefix",
        "description": "CREATE statements must not hardcode database/schema prefix.",
        "pattern": r"(?i)^(?!\s*--)\s*create\s+(or\s+replace\s+)?(table|view|schema)\s+(if\s+not\s+exists\s+)?[a-z0-9_]+\.[a-z0-9_]+(\.[a-z0-9_]+)?",
        "category": "Safety",
    },
    {
        "code": "DO04",
        "name": "security.no_grant_public",
        "description": "GRANT to PUBLIC is not allowed.",
        "pattern": r"(?i)^(?!\s*--).*grant\s+.*\s+to\s+public\b",
        "category": "Security",
    },
    {
        "code": "DO05",
        "name": "safety.drop_if_exists",
        "description": "DROP must use IF EXISTS.",
        "pattern": r"(?i)^\s*DROP\s+(SCHEMA|TABLE|VIEW|DYNAMIC\s+TABLE|STAGE|FILE\s+FORMAT|PROCEDURE|FUNCTION|TASK)\s+(?!IF\s+EXISTS\b)",
        "category": "Safety",
    },
    {
        "code": "DO06",
        "name": "safety.no_use_statements",
        "description": "USE DATABASE/SCHEMA/ROLE statements are not allowed.",
        "pattern": r"(?i)^(?!\s*--)\s*USE\s+(DATABASE|SCHEMA|ROLE)\b",
        "category": "Safety",
    },
    {
        "code": "DO07",
        "name": "datatype.timestamp_tz_only",
        "description": "Only TIMESTAMP_TZ is allowed (no NTZ/LTZ).",
        "pattern": r"(?i)(?<!--.*)\bTIMESTAMP_(NTZ|LTZ)(\s*\(\s*\d+\s*\))?\b",
        "category": "Data Type",
    },
    {
        "code": "DO08",
        "name": "naming.schema_prefix",
        "description": "Schema names must follow {DOMAIN}_{MATURITY}_ prefix pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?(?!RAW_|CUR_|AGG_|GOL_|REF_)[a-z0-9_]+;",
        "category": "Naming",
    },
    {
        "code": "DO09",
        "name": "naming.schema_version",
        "description": "Schema names must end with _vNNN version pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?[a-z0-9_]+(?<!_v\d\d\d);",
        "category": "Naming",
    },
    {
        "code": "DO10",
        "name": "naming.table_pattern",
        "description": "Table names must follow {DOM}{COMP}_{MAT}_{TB}_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?(?!DYNAMIC\s)TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TB_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO11",
        "name": "naming.view_pattern",
        "description": "View names must follow {DOM}{COMP}_{MAT}_{VW}_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_VW_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO12",
        "name": "naming.dynamic_table_pattern",
        "description": "Dynamic Table names must follow {DOM}{COMP}_{MAT}_{DT}_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_DT_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO13",
        "name": "naming.stage_pattern",
        "description": "Stage names must follow {DOM}{COMP}_{MAT}_{ST}_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?STAGE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_ST_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO14",
        "name": "dependency.no_cross_database",
        "description": "Cross-database dependencies are not allowed.",
        "pattern": r"^.*cross_db_true.*$",
        "category": "Dependency",
    },
    {
        "code": "DO15",
        "name": "dependency.no_cross_schema",
        "description": "Cross-schema dependencies are not allowed.",
        "pattern": r"^.*cross_schema_true.*$",
        "category": "Dependency",
    },
    {
        "code": "DO16",
        "name": "security.no_grant_all",
        "description": "GRANT ALL PRIVILEGES is not allowed.",
        "pattern": r"(?i)^(?!\s*--)\s*GRANT\s+ALL\s+(PRIVILEGES\s+)?ON\b",
        "category": "Security",
    },
    {
        "code": "DO17",
        "name": "security.no_accountadmin",
        "description": "ACCOUNTADMIN usage in SQL scripts is not allowed.",
        "pattern": r"(?i)^(?!\s*--)\s*(USE\s+ROLE|SET\s+ROLE|GRANT\s+.*TO\s+ROLE|GRANT\s+ROLE)\s+.*\bACCOUNTADMIN\b",
        "category": "Security",
    },
    {
        "code": "DO18",
        "name": "security.no_plaintext_password",
        "description": "Plaintext passwords in DDL are not allowed.",
        "pattern": r"(?i)^(?!\s*--)\s*.*PASSWORD\s*=\s*'[^']+'",
        "category": "Security",
    },
    {
        "code": "DO19",
        "name": "quality.no_select_star",
        "description": "SELECT * is not allowed. Use explicit column lists.",
        "pattern": r"(?i)^(?!\s*--)\s*SELECT\s+\*\s+FROM\b",
        "category": "Quality",
    },
    {
        "code": "DO20",
        "name": "datatype.no_float",
        "description": "FLOAT/DOUBLE/REAL not allowed. Use NUMBER(p,s).",
        "pattern": r"(?i)(?<!--.*)\b(FLOAT|DOUBLE|REAL)\b",
        "category": "Data Type",
    },
    {
        "code": "DO21",
        "name": "datatype.varchar_length",
        "description": "VARCHAR must have explicit length.",
        "pattern": r"(?i)(?<!--.*)\bVARCHAR\s*[^(]",
        "category": "Data Type",
    },
    {
        "code": "DO22",
        "name": "quality.table_comment",
        "description": "CREATE TABLE must include COMMENT.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TABLE\s+(?!.*\bCOMMENT\b).*;\s*$",
        "category": "Quality",
    },
    {
        "code": "DO23",
        "name": "quality.no_order_in_view",
        "description": "ORDER BY in view definitions is not allowed.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\b[\s\S]*?\bORDER\s+BY\b",
        "category": "Quality",
    },
    {
        "code": "DO24",
        "name": "quality.copy_on_error",
        "description": "COPY INTO must include ON_ERROR clause.",
        "pattern": r"(?i)^(?!\s*--)\s*COPY\s+INTO\s+(?!.*\bON_ERROR\b).*;\s*$",
        "category": "Quality",
    },
    {
        "code": "DO25",
        "name": "quality.dt_target_lag",
        "description": "Dynamic Tables must specify TARGET_LAG.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?!.*\bTARGET_LAG\b)",
        "category": "Quality",
    },
    {
        "code": "DO26",
        "name": "naming.file_format_pattern",
        "description": "File Format names must follow {DOM}{COMP}_{MAT}_FF_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?FILE\s+FORMAT\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_FF_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO27",
        "name": "naming.procedure_pattern",
        "description": "Stored Procedure names must follow {DOM}{COMP}_{MAT}_SP_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_SP_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
    {
        "code": "DO28",
        "name": "naming.task_pattern",
        "description": "Task names must follow {DOM}{COMP}_{MAT}_TK_ pattern.",
        "pattern": r"(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TASK\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TK_)[A-Z_][A-Z0-9_]*",
        "category": "Naming",
    },
]


def scan_raw_sql(raw_sql, rules):
    """Scan raw SQL text against all regex rules. Returns list of violations."""
    violations = []
    lines = raw_sql.split("\n")
    for line_no, line in enumerate(lines, start=1):
        for rule in rules:
            if re.search(rule["pattern"], line):
                violations.append({
                    "rule": rule["code"],
                    "name": rule["name"],
                    "category": rule["category"],
                    "description": rule["description"],
                    "line": line_no,
                    "text": line.strip(),
                })
    return violations
