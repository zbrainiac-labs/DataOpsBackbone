"""Tests for sqlfluff_to_sonar.py."""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "github-runner"))

from sqlfluff_to_sonar import convert


SAMPLE_SQLFLUFF_OUTPUT = [
    {
        "filepath": "structure/tables.sql",
        "violations": [
            {
                "code": "LT01",
                "start_line_no": 5,
                "description": "Expected single space after comma.",
            },
            {
                "code": "AM04",
                "start_line_no": 10,
                "description": "Query produces an ambiguous result.",
            },
            {
                "code": "PRS",
                "start_line_no": 1,
                "description": "Parse error (should be skipped).",
            },
        ],
    },
    {
        "filepath": "sources/definitions/ref.sql",
        "violations": [
            {
                "code": "LT01",
                "start_line_no": 1,
                "description": "Skipped path.",
            },
        ],
    },
]


class TestConvert:
    def test_basic_conversion(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "sqlfluff.json"
            output_path = Path(tmpdir) / "sonar.json"
            input_path.write_text(json.dumps(SAMPLE_SQLFLUFF_OUTPUT))

            count = convert(str(input_path), str(output_path))

            result = json.loads(output_path.read_text())
            assert "issues" in result
            assert "rules" in result
            assert count == 2  # PRS skipped, sources/definitions skipped

    def test_skip_rules(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "sqlfluff.json"
            output_path = Path(tmpdir) / "sonar.json"
            input_path.write_text(json.dumps(SAMPLE_SQLFLUFF_OUTPUT))

            convert(str(input_path), str(output_path))

            result = json.loads(output_path.read_text())
            rule_ids = [i["ruleId"] for i in result["issues"]]
            assert "PRS" not in rule_ids

    def test_skip_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "sqlfluff.json"
            output_path = Path(tmpdir) / "sonar.json"
            input_path.write_text(json.dumps(SAMPLE_SQLFLUFF_OUTPUT))

            convert(str(input_path), str(output_path))

            result = json.loads(output_path.read_text())
            filepaths = [i["primaryLocation"]["filePath"] for i in result["issues"]]
            assert all("sources/definitions" not in p for p in filepaths)

    def test_impact_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "sqlfluff.json"
            output_path = Path(tmpdir) / "sonar.json"
            input_path.write_text(json.dumps(SAMPLE_SQLFLUFF_OUTPUT))

            convert(str(input_path), str(output_path))

            result = json.loads(output_path.read_text())
            rules_by_id = {r["id"]: r for r in result["rules"]}
            assert rules_by_id["LT01"]["impacts"][0]["severity"] == "LOW"
            assert rules_by_id["AM04"]["impacts"][0]["severity"] == "MEDIUM"

    def test_empty_input(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "sqlfluff.json"
            output_path = Path(tmpdir) / "sonar.json"
            input_path.write_text("[]")

            count = convert(str(input_path), str(output_path))
            assert count == 0
