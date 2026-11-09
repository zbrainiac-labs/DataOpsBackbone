"""Tests for neutralize_jinja.py (issue #45)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "github-runner"))

from neutralize_jinja import is_dcm_project, neutralize, run

DCM_MANIFEST = "manifest_version: 2\ntype: DCM_PROJECT\ndefault_target: 'DEV'\n"


def test_expression_becomes_identifier():
    sql = "INSERT INTO {{ db }}.{{ schema }}.T (A, B) VALUES (1, 2);"
    assert neutralize(sql) == 'INSERT INTO "JINJA_DB"."JINJA_SCHEMA".T (A, B) VALUES (1, 2);'


def test_expression_without_spaces_and_filters():
    assert neutralize("{{db}}.{{ schema | upper }}.T") == '"JINJA_DB"."JINJA_SCHEMA".T'
    assert neutralize("{{ cfg.wh }}") == '"JINJA_CFG_WH"'


def test_blocks_are_blanked_and_line_numbers_kept():
    sql = "{% set s = 'STARTED' %}\nDEFINE TASK X\n{# multi\nline #}\nAS SELECT 1;\n"
    out = neutralize(sql)
    assert out.count("\n") == sql.count("\n")
    assert out.splitlines()[1] == "DEFINE TASK X"
    assert out.splitlines()[4] == "AS SELECT 1;"
    assert "{%" not in out
    assert "{#" not in out


def test_insert_without_columns_stays_detectable():
    # neutralizing must not hide a real C003 violation
    assert neutralize("INSERT INTO {{ db }}.T VALUES (1);") == 'INSERT INTO "JINJA_DB".T VALUES (1);'


def test_plain_sql_unchanged():
    sql = "SELECT '{not jinja}' AS X FROM T;"
    assert neutralize(sql) == sql


def test_only_dcm_projects_are_rewritten(tmp_path: Path):
    (tmp_path / "a.sql").write_text("SELECT {{ x }};")
    assert not is_dcm_project(tmp_path)
    assert run(tmp_path) == 0
    assert (tmp_path / "a.sql").read_text() == "SELECT {{ x }};"


def test_dcm_project_rewrites_sql_and_skips_out(tmp_path: Path):
    (tmp_path / "manifest.yml").write_text(DCM_MANIFEST)
    (tmp_path / "sources" / "definitions").mkdir(parents=True)
    (tmp_path / "sources/definitions/t.sql").write_text("DEFINE TABLE {{ db }}.{{ schema }}.T (A INT);")
    (tmp_path / "sqlunit").mkdir()
    (tmp_path / "sqlunit/tests.sqltest").write_text("x | SELECT 1 FROM {{ db }}.T; | 1")
    (tmp_path / "out").mkdir()
    (tmp_path / "out/r.sql").write_text("SELECT {{ db }};")
    (tmp_path / "app.py").write_text("x = '{{ db }}'")
    assert run(tmp_path) == 2
    assert (tmp_path / "sources/definitions/t.sql").read_text() == 'DEFINE TABLE "JINJA_DB"."JINJA_SCHEMA".T (A INT);'
    assert (tmp_path / "out/r.sql").read_text() == "SELECT {{ db }};"
    assert (tmp_path / "app.py").read_text() == "x = '{{ db }}'"


def test_txt_prefix_rule_does_not_see_a_literal_prefix():
    # sonar-rules-setup.sh: Disallow_CREATE_statements_with_hardcoded_database_or_schema_prefix
    prefix_rule = re.compile(r"(?i)^(?!\s*--)\s*create\s+(or\s+replace\s+)?(table|view|schema)\s+"
                             r"(if\s+not\s+exists\s+)?[a-z0-9_]+\.[a-z0-9_]+(\.[a-z0-9_]+)?")
    sql = "CREATE SCHEMA IF NOT EXISTS {{ db }}.{{ schema }};"
    assert not prefix_rule.search(neutralize(sql))
