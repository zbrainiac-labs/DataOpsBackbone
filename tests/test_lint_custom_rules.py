"""Tests for the custom regex rules (DO01-DO28) via scan_raw_sql."""
from __future__ import annotations

import importlib.util
from pathlib import Path

_plugin_path = Path(__file__).resolve().parent.parent / "sqlfluff" / "plugins" / "dataops_rules" / "__init__.py"
_spec = importlib.util.spec_from_file_location("dataops_rules", _plugin_path)
_module = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(_module)  # type: ignore[union-attr]
RULES = _module.RULES  # type: ignore[attr-defined]
scan_raw_sql = _module.scan_raw_sql  # type: ignore[attr-defined]


class TestScanRawSql:
    def test_good_sql_has_no_violations(self, good_sql: str) -> None:
        violations = scan_raw_sql(good_sql, RULES)
        assert len(violations) == 0, (
            f"Expected 0 violations in good_example.sql, got {len(violations)}: "
            + ", ".join(f"[{v['rule']}] line {v['line']}: {v['text']}" for v in violations[:5])
        )

    def test_bad_sql_has_violations(self, bad_sql: str) -> None:
        violations = scan_raw_sql(bad_sql, RULES)
        assert len(violations) > 0, "Expected violations in bad_example.sql"

    def test_bad_sql_catches_grant_to_public(self, bad_sql: str) -> None:
        violations = scan_raw_sql(bad_sql, RULES)
        rule_codes = {v["rule"] for v in violations}
        assert "DO04" in rule_codes, "Expected DO04 (GRANT TO PUBLIC) in bad_example.sql"

    def test_bad_sql_catches_accountadmin(self, bad_sql: str) -> None:
        violations = scan_raw_sql(bad_sql, RULES)
        rule_codes = {v["rule"] for v in violations}
        assert "DO17" in rule_codes, "Expected DO17 (ACCOUNTADMIN) in bad_example.sql"

    def test_empty_sql(self) -> None:
        violations = scan_raw_sql("", RULES)
        assert len(violations) == 0

    def test_single_violation(self) -> None:
        sql = "GRANT SELECT ON TABLE foo TO PUBLIC;"
        violations = scan_raw_sql(sql, RULES)
        do04 = [v for v in violations if v["rule"] == "DO04"]
        assert len(do04) > 0, "Expected DO04 for GRANT TO PUBLIC"
