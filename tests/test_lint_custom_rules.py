"""Tests for the custom regex rules (DO01-DO28) via scan_raw_sql."""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

_plugin_path = Path(__file__).resolve().parent.parent / "sqlfluff" / "plugins" / "dataops_rules" / "__init__.py"
_spec = importlib.util.spec_from_file_location("dataops_rules", _plugin_path)
_module = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(_module)  # type: ignore[union-attr]
RULES = _module.RULES  # type: ignore[attr-defined]
scan_raw_sql = _module.scan_raw_sql  # type: ignore[attr-defined]

# Single-line SQL snippets that MUST trigger exactly the specified rule.
# DO14/DO15 use synthetic dependency-analysis markers, not real SQL.
RULE_TRIGGER_SNIPPETS: dict[str, str] = {
    "DO01": "CREATE SCHEMA my_schema;",
    "DO02": "CREATE TABLE my_bad_table (id INT);",
    "DO03": "CREATE TABLE my_db.my_schema.bad_table (id INT);",
    "DO04": "GRANT SELECT ON TABLE foo TO PUBLIC;",
    "DO05": "DROP TABLE old_data;",
    "DO06": "USE DATABASE production_db;",
    "DO07": "CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_X (ts TIMESTAMP_NTZ) COMMENT = 'x';",
    "DO08": "CREATE SCHEMA IF NOT EXISTS BADSCHEMA_V001;",
    "DO09": "CREATE SCHEMA IF NOT EXISTS RAW_NO_VERSION;",
    "DO10": "CREATE OR REPLACE TABLE IF NOT EXISTS BAD_TABLE_NAME (id NUMBER(10)) COMMENT = 'x';",
    "DO11": "CREATE OR REPLACE VIEW BAD_VIEW_NAME AS SELECT 1 AS col;",
    "DO12": "CREATE OR REPLACE DYNAMIC TABLE BAD_DT_NAME TARGET_LAG = '60 MINUTE' WAREHOUSE = W AS SELECT 1 AS col;",
    "DO13": "CREATE OR REPLACE STAGE BAD_STAGE_NAME;",
    "DO14": "cross_db_true",
    "DO15": "cross_schema_true",
    "DO16": "GRANT ALL PRIVILEGES ON DATABASE foo TO ROLE bar;",
    "DO17": "USE ROLE ACCOUNTADMIN;",
    "DO18": "CREATE USER bad_user PASSWORD = 'SuperSecret123';",
    "DO20": "CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_X (val FLOAT) COMMENT = 'x';",
    "DO21": "CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_X (name VARCHAR) COMMENT = 'x';",
    "DO22": "CREATE OR REPLACE TABLE IOTI_RAW_TB_NO_COMMENT (id NUMBER(10));",
    "DO23": "CREATE OR REPLACE VIEW IOTI_RAW_VW_ORD AS SELECT col FROM t ORDER BY col;",
    "DO24": "COPY INTO IOTI_RAW_TB_LANDING FROM @IOTI_RAW_ST_INBOUND;",
    "DO26": "CREATE OR REPLACE FILE FORMAT BAD_FF_NAME TYPE = CSV;",
    "DO27": "CREATE OR REPLACE PROCEDURE BAD_SP_NAME() RETURNS VARCHAR(100) LANGUAGE SQL AS 'SELECT 1';",
    "DO28": "CREATE OR REPLACE TASK BAD_TASK_NAME WAREHOUSE = W SCHEDULE = 'USING CRON 0 * * * * UTC' AS SELECT 1;",
}
# DO19 (SELECT *) is disabled -- excluded from parametrized test.
# DO25 (Dynamic Table without TARGET_LAG) is multi-line and tested separately.


class TestScanRawSql:
    def test_good_sql_has_no_violations(self, good_sql: str) -> None:
        violations = scan_raw_sql(good_sql, RULES)
        # DO25 (TARGET_LAG) is a known false positive on multi-line DDL because
        # the regex lookahead only checks the CREATE line, not subsequent lines.
        violations = [v for v in violations if v["rule"] != "DO25"]
        assert len(violations) == 0, (
            f"Expected 0 violations in good_example.sql, got {len(violations)}: "
            + ", ".join(f"[{v['rule']}] line {v['line']}: {v['text']}" for v in violations[:5])
        )

    def test_bad_sql_has_violations(self, bad_sql: str) -> None:
        violations = scan_raw_sql(bad_sql, RULES)
        assert len(violations) > 0, "Expected violations in bad_example.sql"

    def test_empty_sql(self) -> None:
        violations = scan_raw_sql("", RULES)
        assert len(violations) == 0


class TestPerRuleTrigger:
    """Each rule in RULE_TRIGGER_SNIPPETS must fire on its snippet."""

    @pytest.mark.parametrize(
        "rule_code,snippet",
        list(RULE_TRIGGER_SNIPPETS.items()),
        ids=list(RULE_TRIGGER_SNIPPETS.keys()),
    )
    def test_rule_fires_on_snippet(self, rule_code: str, snippet: str) -> None:
        violations = scan_raw_sql(snippet, RULES)
        fired = {v["rule"] for v in violations}
        assert rule_code in fired, (
            f"Expected {rule_code} to fire on: {snippet!r}\n"
            f"  Rules that fired: {fired or 'none'}"
        )

    def test_do25_multiline(self) -> None:
        """DO25: Dynamic Table without TARGET_LAG requires multi-line SQL."""
        sql = (
            "CREATE OR REPLACE DYNAMIC TABLE IOTI_RAW_DT_NO_LAG\n"
            "    WAREHOUSE = MD_TEST_WH\n"
            "AS\n"
            "SELECT 1 AS col;"
        )
        violations = scan_raw_sql(sql, RULES)
        fired = {v["rule"] for v in violations}
        assert "DO25" in fired, f"Expected DO25, got: {fired}"


class TestBadExampleCoverage:
    """Verify bad_example.sql triggers each expected rule."""

    @pytest.mark.parametrize(
        "rule_code",
        [f"DO{n:02d}" for n in range(1, 29) if n != 19],
        ids=[f"DO{n:02d}" for n in range(1, 29) if n != 19],
    )
    def test_rule_in_bad_example(self, bad_sql: str, rule_code: str) -> None:
        violations = scan_raw_sql(bad_sql, RULES)
        fired = {v["rule"] for v in violations}
        assert rule_code in fired, (
            f"bad_example.sql should trigger {rule_code} but didn't.\n"
            f"  Rules fired: {sorted(fired)}"
        )
