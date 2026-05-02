#!/usr/bin/env python3
"""Convert SQLFluff JSON output to SonarQube Generic Issue format."""
import json
import sys

SKIP_RULES = {'PRS', 'CP01'}
SKIP_PATHS = {'sources/definitions/', '/out/', '/.scannerwork/'}

SEVERITY_MAP = {
    'LT01': 'INFO', 'LT02': 'INFO', 'LT06': 'INFO',
    'LT08': 'INFO', 'LT09': 'INFO', 'LT10': 'INFO',
    'LT12': 'INFO', 'LT14': 'INFO',
    'CP02': 'MINOR', 'CP04': 'MINOR',
    'AL01': 'MINOR', 'AL02': 'MINOR', 'AL08': 'MINOR',
    'AM01': 'MINOR', 'AM03': 'MINOR', 'AM04': 'MINOR',
    'AM05': 'MAJOR', 'AM09': 'MINOR',
    'RF02': 'MINOR', 'RF03': 'MINOR', 'RF04': 'MAJOR',
    'ST06': 'MINOR', 'ST07': 'MINOR', 'ST09': 'MINOR',
}

with open(sys.argv[1]) as f:
    data = json.load(f)

issues = []
for file_result in data:
    filepath = file_result.get('filepath', '')
    if any(s in filepath for s in SKIP_PATHS):
        continue
    for v in file_result.get('violations', []):
        code = v.get('code', '')
        if code in SKIP_RULES:
            continue
        issues.append({
            'engineId': 'sqlfluff',
            'ruleId': code,
            'severity': SEVERITY_MAP.get(code, 'MINOR'),
            'type': 'CODE_SMELL',
            'primaryLocation': {
                'message': v.get('description', ''),
                'filePath': filepath,
                'textRange': {'startLine': v.get('start_line_no', 1)}
            }
        })

with open(sys.argv[2], 'w') as f:
    json.dump({'issues': issues}, f, indent=2)

print(f'SQLFluff: {len(issues)} issues written to {sys.argv[2]}')
