#!/usr/bin/env python3
"""Make DCM SQL parseable for SonarQube's AST-based SQL Code Checker (SQLCC).

DCM definitions use Jinja (``{{ db }}.{{ schema }}.T``, ``{% if %}``). The
gretard/sonar-sql-plugin cannot parse it and reports false positives such as
SQLCC:C003 ("column list not specified") on INSERTs that do list their columns
(issue #45). This rewrites a *copy* of the project before the scan:

  {{ var }} / {{ var | filter }}  ->  "JINJA_VAR"    (quoted identifier)
  {% ... %}, {# ... #}            ->  spaces          (newlines kept)

The identifier is quoted so the txt: regex rules (e.g. hardcoded db/schema
prefix, ``[a-z0-9_]+\.``) still see a templated name, not a literal prefix.
Line count and line numbers are unchanged, so issue locations stay correct.
Only runs for DCM projects (manifest.yml with ``type: DCM_PROJECT``).

Usage: neutralize_jinja.py <project_dir>      # rewrites *.sql / *.sqltest in place
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

EXPR = re.compile(r"\{\{([^}]*)\}\}")
NAME = re.compile(r"[A-Za-z_][\w.]*")
BLOCK = re.compile(r"\{%.*?%\}|\{#.*?#\}", re.S)
SUFFIXES = {".sql", ".sqltest"}
SKIP_DIRS = {".git", "out", ".scannerwork", "node_modules", "venv", ".venv"}


def _expr(m: re.Match) -> str:
    name = NAME.match(m.group(1).strip())
    return f'"JINJA_{(name.group(0) if name else "expr").replace(".", "_").upper()}"'


def _blank(m: re.Match) -> str:
    # keep newlines so later lines keep their numbers
    return re.sub(r"[^\n]", " ", m.group(0))


def neutralize(text: str) -> str:
    return EXPR.sub(_expr, BLOCK.sub(_blank, text))


def is_dcm_project(root: Path) -> bool:
    manifest = root / "manifest.yml"
    return manifest.is_file() and re.search(
        r"^type:\s*['\"]?DCM_PROJECT", manifest.read_text(), re.M) is not None


def run(root: Path) -> int:
    if not is_dcm_project(root):
        return 0
    changed = 0
    for path in root.rglob("*"):
        if path.suffix not in SUFFIXES or not path.is_file():
            continue
        if SKIP_DIRS.intersection(path.relative_to(root).parts):
            continue
        text = path.read_text()
        new = neutralize(text)
        if new != text:
            path.write_text(new)
            changed += 1
    return changed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(f"neutralize_jinja: {run(Path(sys.argv[1]))} file(s) rewritten")
