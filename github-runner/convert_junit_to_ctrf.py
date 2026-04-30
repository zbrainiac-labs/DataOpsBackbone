#!/usr/bin/env python3
"""
Convert JUnit XML test reports to CTRF JSON format.

Usage:
    python3 convert_junit_to_ctrf.py /path/to/sql-unit-reports

Walks all subdirectories, finds TEST_*.xml files, converts each to
a corresponding .json file in the same directory.
"""

import sys
import os
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def convert_junit_xml_to_ctrf(xml_path: Path) -> dict:
    tree = ET.parse(xml_path)
    root = tree.getroot()

    if root.tag == "testsuites":
        suites = list(root)
    elif root.tag == "testsuite":
        suites = [root]
    else:
        raise ValueError(f"Unexpected root tag: {root.tag}")

    tests = []
    total = 0
    passed = 0
    failed = 0
    skipped = 0

    for suite in suites:
        suite_name = suite.get("name", "SQLValidation")
        for tc in suite.findall("testcase"):
            total += 1
            name = tc.get("name", "Unnamed")
            time_sec = float(tc.get("time", "0"))
            duration_ms = int(time_sec * 1000) if time_sec > 0 else 1

            failure = tc.find("failure")
            skip = tc.find("skipped")

            if failure is not None:
                status = "failed"
                message = failure.get("message", failure.text or "")
                failed += 1
            elif skip is not None:
                status = "skipped"
                message = skip.get("message", "")
                skipped += 1
            else:
                status = "passed"
                message = ""
                passed += 1

            tests.append({
                "name": name,
                "status": status,
                "duration": duration_ms,
                "message": message,
                "suite": suite_name
            })

    total_time_str = suites[0].get("time", "0") if suites else "0"
    total_time_ms = int(float(total_time_str) * 1000)

    ctrf = {
        "reportFormat": "CTRF",
        "specVersion": "0.0.1",
        "results": {
            "tool": {"name": "sql_validation_v4"},
            "summary": {
                "tests": total,
                "passed": passed,
                "failed": failed,
                "skipped": skipped,
                "pending": 0,
                "other": 0,
                "start": 0,
                "stop": total_time_ms
            },
            "tests": tests,
            "environment": {
                "projectName": suite_name
            }
        }
    }
    return ctrf


def main():
    if len(sys.argv) < 2:
        print("Usage: convert_junit_to_ctrf.py <report-directory>")
        sys.exit(1)

    report_dir = Path(sys.argv[1])
    if not report_dir.is_dir():
        print(f"❌ Not a directory: {report_dir}")
        sys.exit(1)

    xml_files = sorted(report_dir.rglob("TEST_*.xml"))
    if not xml_files:
        print(f"No TEST_*.xml files found in {report_dir}")
        sys.exit(0)

    converted = 0
    errors = 0
    for xml_path in xml_files:
        json_path = xml_path.with_suffix(".json")
        try:
            ctrf = convert_junit_xml_to_ctrf(xml_path)
            with open(json_path, "w") as f:
                json.dump(ctrf, f, indent=2)
            converted += 1
            print(f"  ✅ {xml_path.name} -> {json_path.name}")
        except Exception as e:
            errors += 1
            print(f"  ❌ {xml_path.name}: {e}")

    print(f"\n📊 Converted {converted} files, {errors} errors out of {len(xml_files)} total.")


if __name__ == "__main__":
    main()
