#!/usr/bin/env python3
import json, sys, os
from xml.etree.ElementTree import Element, SubElement, tostring

def convert(ctrf_path: str, output_path: str) -> None:
    with open(ctrf_path) as f:
        report = json.load(f)

    root = Element("testExecutions", version="1")
    tests = report.get("results", {}).get("tests", [])

    file_groups = {}
    for test in tests:
        file_path = test.get("filePath", "sqlunit/tests.sqltest")
        file_groups.setdefault(file_path, []).append(test)

    for file_path, file_tests in file_groups.items():
        file_elem = SubElement(root, "file", path=file_path)
        for test in file_tests:
            duration = str(test.get("duration", 0))
            tc = SubElement(file_elem, "testCase", name=test["name"], duration=duration)

            if test["status"] == "failed":
                msg = test.get("message", "Test failed")
                failure = SubElement(tc, "failure", message=msg)
                if test.get("trace"):
                    failure.text = test["trace"]
            elif test["status"] == "skipped":
                SubElement(tc, "skipped", message="Skipped")

    with open(output_path, "wb") as f:
        f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(tostring(root, encoding="unicode").encode("utf-8"))

    print(f"Converted {len(tests)} tests to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <ctrf_input.json> <sonar_output.xml>")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
