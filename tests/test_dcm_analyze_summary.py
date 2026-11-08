"""Tests for github-runner/dcm_analyze_summary.py and the exit-65 handling in lib.sh retry."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from tests.conftest import GITHUB_RUNNER_DIR

sys.path.insert(0, str(GITHUB_RUNNER_DIR))

from dcm_analyze_summary import EXIT_INVALID, iter_issues, main, summarize  # noqa: E402


def _issue(severity: str, code: str = "001662", line: int = 467, msg: str = "Column lineage") -> dict[str, Any]:
    return {"source_position": {"line": line, "column": 0}, "message": msg, "code": code, "severity": severity}


def _result(*per_definition: dict[str, Any], file_level: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    # Shape of `snow dcm raw-analyze --save-output` (CLI 3.25): issues per file and per definition
    return {
        "files": [
            {
                "source_path": "sources/definitions/000_infrastructure.sql",
                "definitions": [],
                "issues": file_level or [],
            },
            {
                "source_path": "sources/definitions/310_streams.sql",
                "definitions": [{"id": {"name": "S"}, "issues": [i]} for i in per_definition],
                "issues": [],
            },
        ],
        "issues": [],
    }


def test_finds_issues_at_every_level_with_their_file() -> None:
    found = list(iter_issues(_result(_issue("INFO"), file_level=[_issue("ERROR", line=5)])))
    assert sorted((s, i["severity"]) for s, i in found) == [
        ("sources/definitions/000_infrastructure.sql", "ERROR"),
        ("sources/definitions/310_streams.sql", "INFO"),
    ]


def test_info_only_passes_and_is_grouped() -> None:
    rc, lines = summarize(_result(*[_issue("INFO")] * 21), cli_exit=1, annotate=False)
    assert rc == 0
    assert "  INFO    001662 21x: Column lineage" in lines
    assert lines[-1] == "  Analyze issues: 21 total, 0 blocking (non-INFO), CLI exit 1"


def test_blocking_issue_fails_with_65_and_annotates_file_and_line() -> None:
    rc, lines = summarize(
        _result(_issue("INFO"), _issue("ERROR", "002003", 12, "Object  does\n not exist")), cli_exit=1, annotate=True
    )
    assert rc == EXIT_INVALID == 65
    assert (
        "::error file=sources/definitions/310_streams.sql,line=12::DCM analyze ERROR 002003: Object does not exist"
        in lines
    )


def test_warning_and_unknown_severity_block() -> None:
    rc, lines = summarize(_result(_issue("WARNING"), _issue("")), cli_exit=1, annotate=True)
    assert rc == 65
    assert lines[0].startswith("::warning file=")
    assert lines[1].startswith("::error file=")


def test_caps_listed_blocking_issues() -> None:
    rc, lines = summarize(_result(*[_issue("ERROR", line=n) for n in range(25)]), cli_exit=1, annotate=False)
    assert rc == 65
    assert sum(1 for x in lines if x.startswith("  ERROR")) == 20
    assert "5 more blocking issues" in "\n".join(lines)


def test_missing_or_broken_result_file_returns_1(tmp_path: Path) -> None:
    assert main(["x", str(tmp_path / "missing.json")]) == 1
    broken = tmp_path / "broken.json"
    broken.write_text("{not json")
    assert main(["x", str(broken)]) == 1
    ok = tmp_path / "ok.json"
    ok.write_text(json.dumps(_result(_issue("INFO"))))
    assert main(["x", str(ok), "1"]) == 0


def _bash(tmp_path: Path, body: str) -> subprocess.CompletedProcess[str]:
    script = tmp_path / "r.sh"
    script.write_text(f'#!/bin/bash\nset -Eeuo pipefail\nsource "{GITHUB_RUNNER_DIR / "lib.sh"}"\n{body}\n')
    env = {k: v for k, v in os.environ.items() if k != "GITHUB_ACTIONS"}
    return subprocess.run(["bash", str(script)], capture_output=True, text=True, env=env, check=False)


def test_retry_stops_at_once_on_exit_65(tmp_path: Path) -> None:
    res = _bash(tmp_path, f'retry bash -c \'echo run >> "{tmp_path}/n"; exit 65\' || echo "rc=$?"')
    assert (tmp_path / "n").read_text().count("run") == 1
    assert "rc=65" in res.stdout
    assert "Not retrying (exit 65" in res.stderr


def test_retry_still_retries_other_failures(tmp_path: Path) -> None:
    res = _bash(tmp_path, f'retry -n 2 bash -c \'echo run >> "{tmp_path}/n"; exit 1\' || echo "rc=$?"')
    assert (tmp_path / "n").read_text().count("run") == 2
    assert "rc=1" in res.stdout
