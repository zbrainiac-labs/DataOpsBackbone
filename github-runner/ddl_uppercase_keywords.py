#!/usr/bin/env python3
"""Post-process Snowflake GET_DDL() output: uppercase identifiers, fix formatting."""
from __future__ import annotations

import sys
import re
from typing import Iterable

IDENT_PATTERN = re.compile(r'(?<!["\'])(?<!\w)([a-z_][a-z0-9_]*)(?!\w)(?!["\'])', re.IGNORECASE)

def uppercase_outside_strings(line: str) -> str:
    parts = re.split(r"('[^']*')", line)
    result = []
    for i, part in enumerate(parts):
        if i % 2 == 0:
            part = IDENT_PATTERN.sub(lambda m: m.group(0).upper(), part)
        result.append(part)
    return ''.join(result)

def fix_spacing(line: str) -> str:
    line = re.sub(r'(\w)\(', r'\1 (', line)
    line = re.sub(r'\(\s{2,}', '(', line)
    line = re.sub(r'\s{2,}\)', ')', line)
    return line

def expand_inline_select(line: str) -> list[str]:
    m = re.match(r'^(\s*\)\s*AS\s+)SELECT\s+(.+?)\s+FROM\s+(.+)$', line, re.IGNORECASE)
    if not m:
        return [line]
    prefix = m.group(1)
    cols = m.group(2)
    rest = m.group(3)
    indent = '    '
    col_list = [c.strip() for c in cols.split(',')]
    lines = [prefix + 'SELECT']
    for i, col in enumerate(col_list):
        sep = ',' if i < len(col_list) - 1 else ''
        lines.append(indent + col + sep)
    from_and_rest = 'FROM ' + rest
    parts = re.split(r'\s+((?:INNER\s+|LEFT\s+|RIGHT\s+|FULL\s+|CROSS\s+)?JOIN\s)', from_and_rest, flags=re.IGNORECASE)
    lines.append(parts[0])
    i = 1
    while i < len(parts) - 1:
        lines.append(parts[i].strip() + parts[i+1] if i+1 < len(parts) else parts[i])
        i += 2
    if len(parts) > 1 and len(parts) % 2 == 0:
        lines[-1] += parts[-1]
    return lines

def process_line(raw_line: str) -> list[str]:
    """Process a single DDL line: uppercase, fix spacing, expand inline SELECTs."""
    raw_line = raw_line.rstrip('\n').replace('\t', '    ')
    if raw_line.lstrip().startswith('--'):
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
