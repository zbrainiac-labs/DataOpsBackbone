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
        assert fix_spacing("(  a  )") == "(a)")


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
