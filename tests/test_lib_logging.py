"""Tests for the shell logging helpers in github-runner/lib.sh (issue #37)."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from tests.conftest import GITHUB_RUNNER_DIR

LINE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z (INFO |WARN |ERROR) \[(?P<tag>[^\]]+)\] (?P<msg>.*)$")


def _run(tmp_path: Path, body: str, **env: str) -> subprocess.CompletedProcess[str]:
    script = tmp_path / "demo.sh"
    script.write_text(f'#!/bin/bash\nset -Eeuo pipefail\nsource "{GITHUB_RUNNER_DIR / "lib.sh"}"\n{body}\n')
    clean = {k: v for k, v in os.environ.items() if k not in ("GITHUB_ACTIONS", "LOG_TAG", "GITHUB_JOB")}
    return subprocess.run(["bash", str(script)], capture_output=True, text=True, env={**clean, **env}, check=False)


def test_levels_format_and_tag(tmp_path: Path) -> None:
    res = _run(tmp_path, 'log_info "hello"\nlog_warn "careful"\nlog_error "broken"')
    lines = res.stderr.splitlines()
    assert [LINE.match(x).group(1).strip() for x in lines] == ["INFO", "WARN", "ERROR"]  # type: ignore[union-attr]
    assert all(LINE.match(x).group("tag") == "demo" for x in lines)  # type: ignore[union-attr]
    assert res.stdout == ""


def test_logs_do_not_pollute_command_substitution(tmp_path: Path) -> None:
    res = _run(tmp_path, 'x=$(log_info "noise"; log_warn "more"; echo data)\necho "[$x]"', GITHUB_ACTIONS="true")
    assert res.stdout.strip() == "[data]"


def test_github_annotations_only_for_warn_and_error(tmp_path: Path) -> None:
    res = _run(tmp_path, 'log_info "i"\nlog_warn "w"\nlog_error "e"', GITHUB_ACTIONS="true")
    assert "::warning title=demo::w" in res.stderr
    assert "::error title=demo::e" in res.stderr
    assert "::notice" not in res.stderr
    assert "title=demo::i" not in res.stderr


def test_die_exits_with_code(tmp_path: Path) -> None:
    res = _run(tmp_path, 'die "fatal" 3\necho unreachable')
    assert res.returncode == 3
    assert "unreachable" not in res.stdout
    assert LINE.match(res.stderr.splitlines()[-1]).group("msg") == "fatal"  # type: ignore[union-attr]


def test_log_tag_override_and_retry(tmp_path: Path) -> None:
    res = _run(tmp_path, 'LOG_TAG=custom log_info "x"\nretry -n 1 false || true')
    tags = [LINE.match(x).group("tag") for x in res.stderr.splitlines()]  # type: ignore[union-attr]
    assert tags == ["custom", "demo"]
