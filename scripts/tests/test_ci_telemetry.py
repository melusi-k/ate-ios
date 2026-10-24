import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import urllib.error


SCRIPT = Path(__file__).resolve().parents[1] / "ci-telemetry.py"
SPEC = importlib.util.spec_from_file_location("ci_telemetry", SCRIPT)
telemetry = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(telemetry)


class TimingTests(unittest.TestCase):
    def test_parse_time_handles_missing_and_invalid_values(self):
        self.assertIsNone(telemetry.parse_time(None))
        self.assertIsNone(telemetry.parse_time("not-a-timestamp"))
        self.assertIsNotNone(telemetry.parse_time("2026-10-23T04:00:00Z"))

    def test_seconds_returns_duration_and_null_for_missing_timestamps(self):
        self.assertEqual(
            telemetry.seconds("2026-10-23T04:00:00Z", "2026-10-23T04:00:03Z"),
            3.0,
        )
        self.assertIsNone(telemetry.seconds(None, "2026-10-23T04:00:03Z"))

    def test_negative_duration_is_clamped_to_zero(self):
        self.assertEqual(
            telemetry.seconds("2026-10-23T04:00:03Z", "2026-10-23T04:00:00Z"),
            0.0,
        )


class ReportTests(unittest.TestCase):
    def test_report_uses_accurate_creation_to_start_metric_names(self):
        report = telemetry.build_report(
            {"GITHUB_RUN_ID": "42"},
            {"created_at": "2026-10-23T04:00:00Z", "status": "completed", "conclusion": "success"},
            [{
                "name": "unit",
                "status": "completed",
                "conclusion": "success",
                "started_at": "2026-10-23T04:00:05Z",
                "completed_at": "2026-10-23T04:00:10Z",
                "steps": [{
                    "name": "test", "number": 1, "status": "completed", "conclusion": "success",
                    "started_at": "2026-10-23T04:00:06Z", "completed_at": "2026-10-23T04:00:08Z",
                }],
            }],
        )
        self.assertEqual(report["workflow_creation_to_first_job_start_seconds"], 5.0)
        self.assertEqual(report["jobs"][0]["creation_to_start_seconds"], 5.0)
        self.assertEqual(report["jobs"][0]["duration_seconds"], 5.0)
        self.assertEqual(report["jobs"][0]["steps"][0]["duration_seconds"], 2.0)
        self.assertNotIn("workflow_queue_seconds_to_first_job", report)
        self.assertNotIn("queue_seconds_from_run_creation", report)

    def test_missing_metadata_is_valid_json_and_non_blocking(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {"RUNNER_TEMP": tmp}
            with patch.dict(os.environ, env, clear=True):
                self.assertEqual(telemetry.main(), 0)
            report = json.loads((Path(tmp) / "ate-ci-telemetry.json").read_text())
        self.assertEqual(report["collection_status"], "missing_github_metadata_or_token")
        self.assertEqual(report["jobs"], [])
        self.assertEqual(report["schema_version"], 1)

    def test_api_failure_still_writes_report_and_returns_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {
                "RUNNER_TEMP": tmp,
                "GITHUB_REPOSITORY": "owner/repo",
                "GITHUB_RUN_ID": "42",
                "GITHUB_TOKEN": "test-token",
            }
            with patch.dict(os.environ, env, clear=True), patch.object(
                telemetry, "api_json", side_effect=urllib.error.URLError("private transport detail")
            ):
                self.assertEqual(telemetry.main(), 0)
            report = json.loads((Path(tmp) / "ate-ci-telemetry.json").read_text())
        self.assertEqual(report["collection_status"], "partial_or_unavailable")
        self.assertEqual(report["jobs"], [])

    def test_missing_timing_fields_remain_null(self):
        report = telemetry.build_report(
            {},
            {"created_at": "2026-10-23T04:00:00Z"},
            [{"name": "queued", "steps": []}],
        )
        self.assertIsNone(report["workflow_creation_to_first_job_start_seconds"])
        self.assertIsNone(report["jobs"][0]["duration_seconds"])
        self.assertIsNone(report["jobs"][0]["creation_to_start_seconds"])


if __name__ == "__main__":
    unittest.main()
