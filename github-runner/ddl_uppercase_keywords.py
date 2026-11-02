#!/usr/bin/env python3
"""Post-process Snowflake GET_DDL() output: uppercase identifiers, fix formatting."""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable

IDENT_PATTERN = re.compile(r'(?<!["\'])(?<!\w)([a-z_][a-z0-9_]*)(?!\w)(?!["\'])', re.IGNORECASE)


def uppercase_outside_strings(line: str) -> str:
    parts = re.split(r"('[^']*')", line)
    result = []
    for i, part in enumerate(parts):
        if i % 2 == 0:
            part = IDENT_PATTERN.sub(lambda m: m.group(0).upper(), part)
        result.append(part)
    return "".join(result)


def _strip_spaces_before_close_paren(line: str) -> str:
    """Same as re.sub(r"\\s{2,}\\)", ")", line), in linear time."""
    out: list[str] = []
    last = 0
    for i, ch in enumerate(line):
        if ch != ")":
            continue
        start = i
        while start > last and line[start - 1].isspace():
            start -= 1
        if i - start >= 2:
            out.append(line[last:start])
            last = i
    out.append(line[last:])
    return "".join(out)


def fix_spacing(line: str) -> str:
    line = re.sub(r"(\w)\(", r"\1 (", line)
    line = re.sub(r"\(\s{2,}", "(", line)
    line = _strip_spaces_before_close_paren(line)
    return line


SELECT_HEAD = re.compile(r"^(\s*\)\s*AS\s+)SELECT(\s+)", re.IGNORECASE)
FROM_KEYWORD = re.compile(r"\sFROM\s", re.IGNORECASE)
WHITESPACE_RUN = re.compile(r"\s+")
JOIN_KEYWORD = re.compile(r"((?:INNER|LEFT|RIGHT|FULL|CROSS)\s+JOIN|JOIN)\s", re.IGNORECASE)


def _split_joins(text: str) -> list[str]:
    """re.split(r"\\s+((?:INNER\\s+|LEFT\\s+|RIGHT\\s+|FULL\\s+|CROSS\\s+)?JOIN\\s)", text) without backtracking.

    Returns [segment, keyword, segment, keyword, ...]; each keyword keeps its trailing whitespace char.
    """
    parts: list[str] = []
    last = pos = 0
    while (run := WHITESPACE_RUN.search(text, pos)) is not None:
        kw = JOIN_KEYWORD.match(text, run.end())
        if kw:
            parts += [text[last : run.start()], kw.group(0)]
            last = pos = kw.end()
        else:
            pos = run.end()
    parts.append(text[last:])
    return parts


def _from_split(seg: str) -> tuple[str, str] | None:
    """Earliest split of seg into (cols, rest) as regex `(.+?)\\s+FROM\\s+(.+)` would do."""
    pos = 0
    while (kw := FROM_KEYWORD.search(seg, pos)) is not None:
        j = kw.start()  # whitespace char right before FROM
        run_start = j
        while run_start > 0 and seg[run_start - 1].isspace():
            run_start -= 1
        cols_end = max(run_start, 1)  # cols needs at least one char
        after = seg[j + len(" FROM") :]  # starts with the whitespace after FROM
        rest = after.lstrip()
        if not rest and len(after) >= 2:
            rest = after[-1:]  # \s+ gives back one char so (.+) is non-empty
        if cols_end <= j and rest:
            return seg[:cols_end], rest
        pos = j + 1
    return None


def _split_inline_select(line: str) -> tuple[str, str, str] | None:
    """Split ') AS SELECT <cols> FROM <rest>' into (prefix, cols, rest) without backtracking.

    Same result as the former regex ^(\\s*\\)\\s*AS\\s+)SELECT\\s+(.+?)\\s+FROM\\s+(.+)$,
    which backtracked super-linearly on long lines.
    """
    head = SELECT_HEAD.match(line)
    if not head or not FROM_KEYWORD.search(line, head.start(2)):
        return None
    tail = line[head.start(2) :]  # whitespace after SELECT + remainder
    ws_len = len(head.group(2))
    for consumed in range(ws_len, 0, -1):  # SELECT\s+ is greedy, then backs off
        split = _from_split(tail[consumed:])
        if split:
            return head.group(1), split[0], split[1]
    return None


def expand_inline_select(line: str) -> list[str]:
    split = _split_inline_select(line)
    if not split:
        return [line]
    prefix, cols, rest = split
    indent = "    "
    col_list = [c.strip() for c in cols.split(",")]
    lines = [prefix + "SELECT"]
    for i, col in enumerate(col_list):
        sep = "," if i < len(col_list) - 1 else ""
        lines.append(indent + col + sep)
    from_and_rest = "FROM " + rest
    parts = _split_joins(from_and_rest)
    lines.append(parts[0])
    i = 1
    while i < len(parts) - 1:
        lines.append(parts[i].strip() + parts[i + 1] if i + 1 < len(parts) else parts[i])
        i += 2
    if len(parts) > 1 and len(parts) % 2 == 0:
        lines[-1] += parts[-1]
    return lines


def process_line(raw_line: str) -> list[str]:
    """Process a single DDL line: uppercase, fix spacing, expand inline SELECTs."""
    raw_line = raw_line.rstrip("\n").replace("\t", "    ")
    if raw_line.lstrip().startswith("--"):
        return [raw_line]
    raw_line = uppercase_outside_strings(raw_line)
    raw_line = fix_spacing(raw_line)
    return expand_inline_select(raw_line)


def process_lines(lines: Iterable[str]) -> list[str]:
    """Process multiple DDL lines."""
    output = []
    for line in lines:
        output.extend(process_line(line))
    return output


if __name__ == "__main__":
    for out_line in process_lines(sys.stdin):
        print(out_line)
