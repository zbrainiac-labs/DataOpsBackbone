#!/usr/bin/env python3
"""Post-process Snowflake GET_DDL() output: uppercase identifiers, fix formatting."""
import sys
import re

IDENT_PATTERN = re.compile(r'(?<!["\'])(?<!\w)([a-z_][a-z0-9_]*)(?!\w)(?!["\'])', re.IGNORECASE)

def uppercase_outside_strings(line):
    parts = re.split(r"('[^']*')", line)
    result = []
    for i, part in enumerate(parts):
        if i % 2 == 0:
            part = IDENT_PATTERN.sub(lambda m: m.group(0).upper(), part)
        result.append(part)
    return ''.join(result)

def fix_spacing(line):
    line = re.sub(r'(\w)\(', r'\1 (', line)
    line = re.sub(r'\(\s{2,}', '(', line)
    line = re.sub(r'\s{2,}\)', ')', line)
    return line

def expand_inline_select(line):
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

for raw_line in sys.stdin:
    raw_line = raw_line.rstrip('\n')
    raw_line = raw_line.replace('\t', '    ')
    if raw_line.lstrip().startswith('--'):
        print(raw_line)
        continue
    raw_line = uppercase_outside_strings(raw_line)
    raw_line = fix_spacing(raw_line)
    for out_line in expand_inline_select(raw_line):
        print(out_line)
