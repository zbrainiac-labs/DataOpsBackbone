"""Shared fixtures for DataOpsBackbone tests."""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
GITHUB_RUNNER_DIR = REPO_ROOT / "github-runner"
SQLFLUFF_DIR = REPO_ROOT / "sqlfluff"
TEST_SQL_DIR = SQLFLUFF_DIR / "test_sql"


@pytest.fixture()
def good_sql() -> str:
    return (TEST_SQL_DIR / "good_example.sql").read_text()


@pytest.fixture()
def bad_sql() -> str:
    return (TEST_SQL_DIR / "bad_example.sql").read_text()
