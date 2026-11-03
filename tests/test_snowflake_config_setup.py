"""Tests for the PAT expiry check in github-runner/snowflake-config-setup.sh."""

from __future__ import annotations

import base64
import json
import os
import subprocess
import time
from pathlib import Path

from tests.conftest import GITHUB_RUNNER_DIR

SCRIPT = GITHUB_RUNNER_DIR / "snowflake-config-setup.sh"


def _jwt(exp: int) -> str:
    def b64(obj: dict[str, object]) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")

    return f"{b64({'alg': 'none'})}.{b64({'exp': exp})}.sig"


def _run(tmp_path: Path, days: int) -> subprocess.CompletedProcess[str]:
    token = _jwt(int(time.time()) + days * 86400 + 3600)
    cfg = (
        f'[connections.ci]\naccount = "a"\nuser = "u"\nauthenticator = "programmatic_access_token"\ntoken = "{token}"\n'
    )
    env = {k: v for k, v in os.environ.items() if k not in ("CONNECTION_NAME", "GITHUB_ACTIONS")}
    env.update(HOME=str(tmp_path), SNOW_CONFIG_B64=base64.b64encode(cfg.encode()).decode())
    return subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True, env=env, check=False)


def test_reports_days_left(tmp_path: Path) -> None:
    res = _run(tmp_path, 100)
    assert res.returncode == 0, res.stderr
    assert "PAT valid for 100 more days" in res.stderr
    assert (tmp_path / ".snowflake" / "config.toml").stat().st_mode & 0o777 == 0o600


def test_warns_before_expiry(tmp_path: Path) -> None:
    res = _run(tmp_path, 10)
    assert res.returncode == 0
    assert "PAT expires in 10 days" in res.stderr


def test_fails_when_expired(tmp_path: Path) -> None:
    res = _run(tmp_path, -2)
    assert res.returncode == 1
    assert "PAT has EXPIRED" in res.stderr
