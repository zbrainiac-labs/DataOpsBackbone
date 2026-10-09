"""Tests for ctrf_to_sonar_converter.py."""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "github-runner"))

from ctrf_to_sonar_converter import convert


SAMPLE_CTRF = {
    "results": {
        "tests": [
            {
                "name": "Row count check",
                "status": "passed",
                "duration": 100,
                "filePath": "sqlunit/tests.sqltest",
            },
            {
                "name": "NULL check",
                "status": "failed",
                "duration": 50,
                "message": "Expected 0 but got 3",
                "filePath": "sqlunit/tests.sqltest",
            },
            {
                "name": "Skipped test",
                "status": "skipped",
                "duration": 0,
                "filePath": "sqlunit/tests.sqltest",
            },
        ]
    }
}


class TestConvert:
    def test_produces_valid_xml(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            ctrf_path = Path(tmpdir) / "report.json"
            output_path = Path(tmpdir) / "sonar.xml"
            ctrf_path.write_text(json.dumps(SAMPLE_CTRF))

            convert(str(ctrf_path), str(output_path))

            content = output_path.read_text()
            assert '<?xml version="1.0"' in content
            assert "testExecutions" in content
            assert "Row count check" in content
            assert "NULL check" in content
            assert "<failure" in content
            assert "<skipped" in content

    def test_empty_tests(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            ctrf_path = Path(tmpdir) / "report.json"
            output_path = Path(tmpdir) / "sonar.xml"
            ctrf_path.write_text(json.dumps({"results": {"tests": []}}))

            convert(str(ctrf_path), str(output_path))
            assert output_path.exists()
