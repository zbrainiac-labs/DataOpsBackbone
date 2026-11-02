"""Tests for sqlfluff/lint.py (standalone linter). sqlfluff itself is mocked."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SQLFLUFF_DIR = Path(__file__).resolve().parent.parent / "sqlfluff"
TEST_SQL_DIR = SQLFLUFF_DIR / "test_sql"

_spec = importlib.util.spec_from_file_location("dataops_lint", SQLFLUFF_DIR / "lint.py")
lint = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(lint)  # type: ignore[union-attr]

SQLFLUFF_JSON = json.dumps(
    [
        {"filepath": "a.sql", "violations": [{"code": "LT01", "description": "spacing", "start_line_no": 3}]},
    ]
)


def _fake_run(stdout: str, stderr: str = ""):
    calls: list[list[str]] = []

    def run(cmd, **_kwargs):
        calls.append(cmd)
        return SimpleNamespace(stdout=stdout, stderr=stderr, returncode=0)

    return run, calls


def test_run_sqlfluff_parses_violations(monkeypatch: pytest.MonkeyPatch) -> None:
    run, calls = _fake_run(SQLFLUFF_JSON)
    monkeypatch.setattr(subprocess, "run", run)
    result = lint.run_sqlfluff("a.sql", "/cfg")
    assert result == [{"file": "a.sql", "rule": "LT01", "description": "spacing", "line": 3, "category": "SQLFluff"}]
    assert calls[0][-2:] == ["--config", "/cfg"]


def test_run_sqlfluff_invalid_json_warns(monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture) -> None:
    run, calls = _fake_run("not json", stderr="boom")
    monkeypatch.setattr(subprocess, "run", run)
    assert lint.run_sqlfluff("a.sql", None) == []
    assert "--config" not in calls[0]
    err = capsys.readouterr().err
    assert "Failed to parse SQLFluff JSON" in err
    assert "boom" in err


def test_run_custom_rules_file_and_dir() -> None:
    bad = TEST_SQL_DIR / "bad_example.sql"
    on_file = lint.run_custom_rules(str(bad))
    assert on_file
    assert all(v["file"] == str(bad) for v in on_file)
    on_dir = lint.run_custom_rules(str(TEST_SQL_DIR))
    assert {v["file"] for v in on_dir} >= {str(bad)}


def test_print_text_report_counts(capsys: pytest.CaptureFixture) -> None:
    sf = [{"file": "a.sql", "line": 1, "rule": "LT01", "description": "d"}]
    custom = [{"file": "a.sql", "line": 2, "rule": "DO05", "description": "d", "text": "DROP TABLE x"}]
    assert lint.print_text_report(sf, custom, 5) == 2
    out = capsys.readouterr().out
    assert "Total: 2 violations (1 SQLFluff + 1 custom rules)" in out
    assert "> DROP TABLE x" in out


def test_write_ctrf_report(tmp_path: Path) -> None:
    out = tmp_path / "r.json"
    sf = [{"file": "a.sql", "line": 1, "rule": "LT01", "description": "d"}]
    custom = [{"file": "b.sql", "line": 2, "rule": "DO05", "description": "d", "text": "DROP"}]
    lint.write_ctrf_report(sf, custom, 7, str(out))
    report = json.loads(out.read_text())["results"]
    assert report["summary"]["failed"] == 2
    assert report["summary"]["stop"] == 7
    assert [t["suite"] for t in report["tests"]] == ["SQLFluff", "DataOps Custom Rules"]


def test_main_usage_exit_1(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sys, "argv", ["lint.py"])
    with pytest.raises(SystemExit) as exc:
        lint.main()
    assert exc.value.code == 1


def test_main_json_report_and_exit_code(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(lint, "run_sqlfluff", lambda *_: [])
    written: list[str] = []
    monkeypatch.setattr(lint, "write_ctrf_report", lambda *args: written.append(args[-1]))
    monkeypatch.setattr(sys, "argv", ["lint.py", str(TEST_SQL_DIR / "bad_example.sql"), "--format=json"])
    with pytest.raises(SystemExit) as exc:
        lint.main()
    assert exc.value.code == 1
    assert written[0].endswith("lint_report.json")

    clean = tmp_path / "clean.sql"
    clean.write_text("-- nothing here\n")
    monkeypatch.setattr(sys, "argv", ["lint.py", str(clean)])
    with pytest.raises(SystemExit) as exc:
        lint.main()
    assert exc.value.code == 0
