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

import sys
import os
import json
import subprocess
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from plugins.dataops_rules import RULES, scan_raw_sql


def run_sqlfluff(target, config_path):
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
    except (json.JSONDecodeError, TypeError):
        pass
    return violations


def run_custom_rules(target):
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


def print_text_report(sqlfluff_violations, custom_violations, elapsed_ms):
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


def write_ctrf_report(sqlfluff_violations, custom_violations, elapsed_ms, output_path):
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


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 lint.py <file_or_dir> [--format=text|json]")
        sys.exit(1)

    target = sys.argv[1]
    out_format = "text"
    for arg in sys.argv[2:]:
        if arg.startswith("--format="):
            out_format = arg.split("=", 1)[1]

    config_path = os.path.join(os.path.dirname(__file__), ".sqlfluff")
    if not os.path.exists(config_path):
        config_path = None

    start = time.time()
    sqlfluff_violations = run_sqlfluff(target, config_path)
    custom_violations = run_custom_rules(target)
    elapsed_ms = int((time.time() - start) * 1000)

    total = print_text_report(sqlfluff_violations, custom_violations, elapsed_ms)

    if out_format == "json":
        report_path = os.path.join(os.path.dirname(__file__), "lint_report.json")
        write_ctrf_report(sqlfluff_violations, custom_violations, elapsed_ms, report_path)

    sys.exit(1 if total > 0 else 0)


if __name__ == "__main__":
    main()
