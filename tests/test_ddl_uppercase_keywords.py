"""Tests for ddl_uppercase_keywords.py."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "github-runner"))

from ddl_uppercase_keywords import (
    expand_inline_select,
    fix_spacing,
    process_line,
    process_lines,
    uppercase_outside_strings,
)


class TestUppercaseOutsideStrings:
    def test_lowercase_keywords(self) -> None:
        assert uppercase_outside_strings("create table foo") == "CREATE TABLE FOO"

    def test_preserves_quoted_strings(self) -> None:
        result = uppercase_outside_strings("select 'hello world' from foo")
        assert "'hello world'" in result
        assert "SELECT" in result
        assert "FROM" in result
        assert "FOO" in result


class TestFixSpacing:
    def test_adds_space_before_paren(self) -> None:
        assert fix_spacing("count(*)") == "count (*)"

    def test_removes_extra_spaces_in_parens(self) -> None:
        assert fix_spacing("(  a  )") == "(a)"


class TestExpandInlineSelect:
    def test_no_match_returns_original(self) -> None:
        assert expand_inline_select("CREATE TABLE foo;") == ["CREATE TABLE foo;"]

    def test_expands_select(self) -> None:
        line = ") AS SELECT col1, col2 FROM my_table"
        result = expand_inline_select(line)
        assert len(result) >= 3
        assert "SELECT" in result[0]


class TestProcessLine:
    def test_comment_passthrough(self) -> None:
        assert process_line("  -- this is a comment") == ["  -- this is a comment"]

    def test_basic_processing(self) -> None:
        result = process_line("create table foo;")
        assert result == ["CREATE TABLE FOO;"]

    def test_tabs_replaced(self) -> None:
        result = process_line("\tcreate table foo;")
        assert result[0].startswith("    ")


class TestProcessLines:
    def test_multiple_lines(self) -> None:
        lines = ["create table foo;\n", "-- comment\n", "select * from bar;\n"]
        result = process_lines(lines)
        assert len(result) >= 3
        assert result[0] == "CREATE TABLE FOO;"
        assert result[1] == "-- comment"


class TestRegexRewriteEquivalence:
    """Edge cases pinned from the former backtracking regexes (same output, linear time)."""

    def test_joins_split_on_own_lines(self) -> None:
        line = ") AS SELECT a, b FROM t1 LEFT JOIN t2 ON x INNER  JOIN t3 ON y JOIN t4 ON z"
        assert expand_inline_select(line) == [
            ") AS SELECT",
            "    a,",
            "    b",
            "FROM t1",
            "LEFT JOINt2 ON x",
            "INNER  JOINt3 ON y",
            "JOINt4 ON z",
        ]

    def test_first_from_wins(self) -> None:
        assert expand_inline_select(") AS SELECT a FROM t WHERE x FROM y")[2] == "FROM t WHERE x FROM y"

    def test_whitespace_only_columns_like_before(self) -> None:
        assert expand_inline_select(") AS  SELECT    FROM  t") == [") AS  SELECT", "    ", "FROM t"]

    def test_from_without_table_is_not_expanded(self) -> None:
        line = ")AS SELECT a FROM "
        assert expand_inline_select(line) == [line]

    def test_fix_spacing_before_paren(self) -> None:
        assert fix_spacing("x(a   )") == "x (a)"
        assert fix_spacing("   )") == ")"

    def test_linear_time_on_pathological_input(self) -> None:
        import time

        start = time.perf_counter()
        expand_inline_select(") AS SELECT " + "a " * 3000 + " " * 3000 + "x")
        fix_spacing(" " * 20000 + "x")
        expand_inline_select(") AS SELECT a FROM t" + " " * 20000 + "x")
        assert time.perf_counter() - start < 1.0
