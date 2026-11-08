#!/usr/bin/env python3
"""Summarize a `snow dcm raw-analyze --save-output` result (out/compile_result.json).

Prints blocking issues (anything not INFO) in full, as GitHub annotations when
running in Actions, and only counts INFO notes. Exit codes:
  0   no blocking issues
  65  blocking issues: the definitions are invalid (deterministic, not retried)
  1   the result file is missing or cannot be parsed
"""

from __future__ import annotations

import json
import os
import sys
from collections import Counter
from collections.abc import Iterator
from typing import Any

EXIT_INVALID = 65  # EX_DATAERR; lib.sh `retry` does not repeat it
MAX_SHOWN = 20


def iter_issues(node: Any, source: str = "") -> Iterator[tuple[str, dict[str, Any]]]:
    """Yield (source_path, issue) for every issue, at any depth of the result."""
    if isinstance(node, dict):
        source = str(node.get("source_path", source))
        for key, value in node.items():
            if key == "issues" and isinstance(value, list):
                yield from ((source, i) for i in value if isinstance(i, dict))
            else:
                yield from iter_issues(value, source)
    elif isinstance(node, list):
        for item in node:
            yield from iter_issues(item, source)


def is_blocking(issue: dict[str, Any]) -> bool:
    return str(issue.get("severity", "")).upper() != "INFO"


def format_issue(source: str, issue: dict[str, Any], annotate: bool) -> str:
    line = (issue.get("source_position") or {}).get("line", "")
    message = " ".join(str(issue.get("message", "")).split())
    severity = str(issue.get("severity", "?")).upper()
    code = issue.get("code", "")
    if annotate:
        level = "warning" if severity == "WARNING" else "error"
        props = ",".join(p for p in (f"file={source}" if source else "", f"line={line}" if line != "" else "") if p)
        return f"::{level}{' ' + props if props else ''}::DCM analyze {severity} {code}: {message}"
    return f"  {severity:7} {code} {source or '?'}:{line or '?'} {message}"


def summarize(result: Any, cli_exit: int, annotate: bool) -> tuple[int, list[str]]:
    issues = list(iter_issues(result))
    blocking = [(s, i) for s, i in issues if is_blocking(i)]
    out = [format_issue(s, i, annotate) for s, i in blocking[:MAX_SHOWN]]
    if len(blocking) > MAX_SHOWN:
        out.append(f"  ... {len(blocking) - MAX_SHOWN} more blocking issues, see out/compile_result.json")
    info = Counter(
        (i.get("code", ""), " ".join(str(i.get("message", "")).split())) for s, i in issues if not is_blocking(i)
    )
    for (code, message), count in info.most_common():
        out.append(f"  INFO    {code} {count}x: {message}")
    out.append(f"  Analyze issues: {len(issues)} total, {len(blocking)} blocking (non-INFO), CLI exit {cli_exit}")
    return (EXIT_INVALID if blocking else 0), out


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "out/compile_result.json"
    cli_exit = int(argv[2]) if len(argv) > 2 else 0
    try:
        with open(path) as fh:
            result = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"  Cannot read DCM analyze result {path}: {exc}", file=sys.stderr)
        return 1
    rc, lines = summarize(result, cli_exit, annotate=os.environ.get("GITHUB_ACTIONS") == "true")
    print("\n".join(lines))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
