import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("readiness", ROOT / "release" / "readiness.py")
readiness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(readiness)


class ReadinessEvidenceTests(unittest.TestCase):
    def test_older_completed_run_cannot_replace_newer_snapshot(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 created_at=2026-10-31T01:00:00Z sha=abc -->"
        incoming = {"id": 899, "run_number": 299}
        self.assertTrue(readiness.incoming_run_is_stale(incoming, existing))

    def test_newer_run_can_replace_older_snapshot(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 created_at=2026-10-31T01:00:00Z sha=abc -->"
        incoming = {"id": 901, "run_number": 301}
        self.assertFalse(readiness.incoming_run_is_stale(incoming, existing))

    def test_replayed_same_run_is_idempotent_not_stale(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 created_at=2026-10-31T01:00:00Z sha=abc -->"
        incoming = {"id": 900, "run_number": 300}
        self.assertFalse(readiness.incoming_run_is_stale(incoming, existing))

    def test_unbound_refresh_cannot_erase_existing_evidence(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 created_at=2026-10-31T01:00:00Z sha=abc -->"
        self.assertTrue(readiness.incoming_run_is_stale(None, existing))

    def test_artifact_only_build_is_blocked_when_full_validation_is_skipped(self):
        rd = {"ci": {"build": "pass", "unit": "skipped", "qa": "skipped", "ui": "skipped", "e2e": "skipped"}}
        disposition, _ = readiness.release_disposition(rd, {"pass": 59})
        self.assertEqual(disposition, "BLOCKED")

    def test_all_ci_green_but_unverified_product_items_are_not_ready(self):
        rd = {"ci": {key: "pass" for key in ("build", "unit", "qa", "ui", "e2e")}}
        disposition, _ = readiness.release_disposition(rd, {"pass": 50, "none": 9})
        self.assertEqual(disposition, "NOT READY")

    def test_fully_verified_candidate_still_requires_human_signoff(self):
        rd = {"ci": {key: "pass" for key in ("build", "unit", "qa", "ui", "e2e")}}
        disposition, reason = readiness.release_disposition(rd, {"pass": 59})
        self.assertEqual(disposition, "READY FOR HUMAN SIGN-OFF")
        self.assertIn("not an automatic release approval", reason)


if __name__ == "__main__":
    unittest.main()
