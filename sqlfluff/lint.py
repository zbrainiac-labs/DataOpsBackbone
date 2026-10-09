#!/usr/bin/env python3
"""
DataOps SQL Linter — SQLFluff + custom regex rules.

Runs SQLFluff (Snowflake dialect) for formatting/style rules,
then applies the same 28 regex rules from SonarQube for
safety, naming, security, data type, and quality checks.

Usage:
    python3 lint.py <file_or_dir> [--format=text|json]

Output: CTRF JSON report (same format as sql_validation_v4.sh)
"""

from __future__ import annotations

import sys
import json
import subprocess
import time
import importlib.util
from pathlib import Path
from typing import Any

_plugin_path = Path(__file__).resolve().parent / "plugins" / "dataops_rules" / "__init__.py"
_spec = importlib.util.spec_from_file_location("dataops_rules", _plugin_path)
_module = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(_module)  # type: ignore[union-attr]
RULES = _module.RULES  # type: ignore[attr-defined]
scan_raw_sql = _module.scan_raw_sql  # type: ignore[attr-defined]


def run_sqlfluff(target: str, config_path: str | None) -> list[dict[str, Any]]:
    """Run sqlfluff lint and return parsed violations."""
    cmd = [
        "sqlfluff", "lint",
        target,
        "--dialect", "snowflake",
        "--format", "json",
    ]
    if config_path:
        cmd += ["--config", config_path]

    result = subprocess.run(cmd, capture_output=True, text=True)
    violations = []
    try:
        data = json.loads(result.stdout)
        for file_result in data:
            filepath = file_result.get("filepath", "")
            for v in file_result.get("violations", []):
                violations.append({
                    "file": filepath,
                    "rule": v.get("code", ""),
                    "description": v.get("description", ""),
                    "line": v.get("start_line_no", 0),
                    "category": "SQLFluff",
                })
    except (json.JSONDecodeError, TypeError) as e:
        print(f"WARNING: Failed to parse SQLFluff JSON output: {e}", file=sys.stderr)
        if result.stderr:
            print(f"  SQLFluff stderr: {result.stderr.strip()}", file=sys.stderr)
    return violations


def run_custom_rules(target: str) -> list[dict[str, Any]]:
    """Run custom regex rules on all .sql files."""
    violations = []
    target_path = Path(target)

    if target_path.is_file():
        sql_files = [target_path]
    else:
        sql_files = sorted(target_path.rglob("*.sql"))

    for sql_file in sql_files:
        raw = sql_file.read_text(encoding="utf-8", errors="replace")
        hits = scan_raw_sql(raw, RULES)
        for h in hits:
            h["file"] = str(sql_file)
            violations.append(h)

    return violations


def print_text_report(sqlfluff_violations: list[dict[str, Any]], custom_violations: list[dict[str, Any]], elapsed_ms: int) -> int:
    total_sf = len(sqlfluff_violations)
    total_custom = len(custom_violations)

    print(f"\n{'='*70}")
    print(f" DataOps SQL Linter Results")
    print(f"{'='*70}")

    if sqlfluff_violations:
        print(f"\n--- SQLFluff violations ({total_sf}) ---")
        for v in sqlfluff_violations:
            print(f"  {v['file']}:{v['line']}  [{v['rule']}] {v['description']}")

    if custom_violations:
        print(f"\n--- DataOps custom rules violations ({total_custom}) ---")
        for v in custom_violations:
            print(f"  {v['file']}:{v['line']}  [{v['rule']}] {v['description']}")
            print(f"    > {v['text']}")

    total = total_sf + total_custom
    print(f"\n{'='*70}")
    print(f" Total: {total} violations ({total_sf} SQLFluff + {total_custom} custom rules) in {elapsed_ms}ms")
    print(f"{'='*70}\n")
    return total


def write_ctrf_report(sqlfluff_violations: list[dict[str, Any]], custom_violations: list[dict[str, Any]], elapsed_ms: int, output_path: str) -> None:
    tests = []
    for v in sqlfluff_violations:
        tests.append({
            "name": f"[{v['rule']}] {v['description']}",
            "status": "failed",
            "duration": 0,
            "message": f"{v['file']}:{v['line']}",
            "suite": "SQLFluff",
        })
    for v in custom_violations:
        tests.append({
            "name": f"[{v['rule']}] {v['description']}",
            "status": "failed",
            "duration": 0,
            "message": f"{v['file']}:{v['line']} — {v['text']}",
            "suite": "DataOps Custom Rules",
        })

    total = len(sqlfluff_violations) + len(custom_violations)
    ctrf = {
        "reportFormat": "CTRF",
        "specVersion": "0.0.1",
        "results": {
            "tool": {"name": "dataops-sqlfluff-linter"},
            "summary": {
                "tests": total,
                "passed": 0,
                "failed": total,
                "skipped": 0,
                "pending": 0,
                "other": 0,
                "start": 0,
                "stop": elapsed_ms,
            },
            "tests": tests,
        },
    }
    with open(output_path, "w") as f:
        json.dump(ctrf, f, indent=2)
    print(f"CTRF report: {output_path}")


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 lint.py <file_or_dir> [--format=text|json]")
        sys.exit(1)

    target = sys.argv[1]
    out_format = "text"
    for arg in sys.argv[2:]:
        if arg.startswith("--format="):
            out_format = arg.split("=", 1)[1]

    config_path_obj = Path(__file__).resolve().parent / ".sqlfluff"
    config_path = str(config_path_obj) if config_path_obj.exists() else None

    start = time.time()
    sqlfluff_violations = run_sqlfluff(target, config_path)
    custom_violations = run_custom_rules(target)
    elapsed_ms = int((time.time() - start) * 1000)

    total = print_text_report(sqlfluff_violations, custom_violations, elapsed_ms)

    if out_format == "json":
        report_path = str(Path(__file__).resolve().parent / "lint_report.json")
        write_ctrf_report(sqlfluff_violations, custom_violations, elapsed_ms, report_path)

    sys.exit(1 if total > 0 else 0)


if __name__ == "__main__":
    main()
