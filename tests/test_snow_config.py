"""Tests for local-ci/snow-config.sh (single source for SNOW_CONFIG_B64)."""

from __future__ import annotations

import base64
import os
import re
import subprocess
from pathlib import Path

from tests.conftest import REPO_ROOT

SCRIPT = REPO_ROOT / "local-ci" / "snow-config.sh"


def _parse(b64: str) -> dict[str, dict[str, str]]:
    """Minimal parser for the flat [connections.X] / key = "value" output."""
    conns: dict[str, dict[str, str]] = {}
    current: dict[str, str] = {}
    for line in base64.b64decode(b64).decode().splitlines():
        if m := re.fullmatch(r"\[connections\.([^\]]+)\]", line):
            current = conns.setdefault(m.group(1), {})
        elif m := re.fullmatch(r'(\w+) = "(.*)"', line):
            current[m.group(1)] = m.group(2)
    return conns


def _run(tmp_path: Path, env_text: str) -> subprocess.CompletedProcess[str]:
    env_file = tmp_path / ".env"
    env_file.write_text(env_text)
    clean = {k: v for k, v in os.environ.items() if not k.startswith(("SNOW_", "CONNECTION_NAME", "GITHUB_ACTIONS"))}
    return subprocess.run(
        ["bash", str(SCRIPT)],
        capture_output=True,
        text=True,
        env={**clean, "ENV_FILE": str(env_file)},
        check=False,
    )


def test_builds_pat_config(tmp_path: Path) -> None:
    res = _run(tmp_path, "CONNECTION_NAME=ci\nSNOW_ACCOUNT=acme-xy\nSNOW_USER=SVC_CICD\nSNOW_PAT=secret-token\n")
    assert res.returncode == 0, res.stderr
    conn = _parse(res.stdout)["ci"]
    assert conn["account"] == "acme-xy"
    assert conn["user"] == "SVC_CICD"
    assert conn["authenticator"] == "programmatic_access_token"
    assert conn["token"] == "secret-token"
    assert conn["role"] == "CICD"  # default


def test_optional_values_and_default_connection(tmp_path: Path) -> None:
    res = _run(tmp_path, "SNOW_ACCOUNT=a\nSNOW_USER=u\nSNOW_PAT=p\nSNOW_ROLE=R\nSNOW_WAREHOUSE=WH\n")
    conn = _parse(res.stdout)["default"]
    assert conn["role"] == "R"
    assert conn["warehouse"] == "WH"


def test_missing_pat_fails_without_output(tmp_path: Path) -> None:
    res = _run(tmp_path, "SNOW_ACCOUNT=a\nSNOW_USER=u\n")
    assert res.returncode != 0
    assert res.stdout == ""
    assert "SNOW_PAT" in res.stderr


def test_missing_env_file_fails(tmp_path: Path) -> None:
    clean = {k: v for k, v in os.environ.items() if not k.startswith("SNOW_")}
    res = subprocess.run(
        ["bash", str(SCRIPT)],
        capture_output=True,
        text=True,
        env={**clean, "ENV_FILE": str(tmp_path / "nope.env")},
        check=False,
    )
    assert res.returncode != 0
    assert res.stdout == ""
