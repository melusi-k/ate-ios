import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("readiness", ROOT / "release" / "readiness.py")
readiness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(readiness)


class ReadinessEvidenceTests(unittest.TestCase):
    def test_pilot_display_preserves_existing_rolling_issue_key(self):
        key, title = readiness.rolling_identity("0.1.x", "Internal beta")
        self.assertEqual(key, "rolling|0.1.x|Tier A|Internal beta")
        self.assertEqual(title, "Candidate evidence: 0.1.x Pilot candidate (Internal beta)")

    def test_rolling_identity_keeps_release_lines_distinct(self):
        self.assertNotEqual(readiness.rolling_identity("0.1.x", "Internal beta")[0],
                            readiness.rolling_identity("0.2.x", "Internal beta")[0])

    def test_candidate_report_keeps_evidence_inventory_and_no_second_approval(self):
        key, title = readiness.rolling_identity("0.1.x", "Internal beta")
        body, _, _ = readiness.build_body(key, title, "Internal beta", "0.1.0 (build 0)",
                                          {}, {}, "fixture", None, None)
        self.assertIn("readiness-key: rolling|0.1.x|Tier A|Internal beta", body)
        self.assertIn("#45 owns the Pilot/Launch decision", body)
        self.assertIn("/59 verified", body)
        self.assertNotIn("- [x] Approved", body)
        self.assertNotIn("- [ ] Approved for beta", body)
        self.assertIn("no completed Build IPA run", body)

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

    def test_same_run_rerun_attempt_can_replace_previous_attempt(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 run_attempt=1 created_at=2026-10-31T01:00:00Z sha=abc -->"
        incoming = {"id": 900, "run_number": 300, "run_attempt": 2}
        self.assertFalse(readiness.incoming_run_is_stale(incoming, existing))

    def test_older_attempt_cannot_replace_newer_attempt(self):
        existing = "<!-- readiness-evidence: run_id=900 run_number=300 run_attempt=2 created_at=2026-10-31T01:00:00Z sha=abc -->"
        incoming = {"id": 900, "run_number": 300, "run_attempt": 1}
        self.assertTrue(readiness.incoming_run_is_stale(incoming, existing))

    def test_qa_rows_must_match_both_candidate_sha_and_run_id(self):
        rd = {"sha": "abc123", "id": 900}
        rows = [
            {"item_id": "A-1", "commit_sha": "abc123", "run_id": 900},
            {"item_id": "A-2", "commit_sha": "older", "run_id": 900},
            {"item_id": "A-3", "commit_sha": "abc123", "run_id": 899},
            {"item_id": "A-4", "commit_sha": None, "run_id": None},
        ]
        self.assertEqual([r["item_id"] for r in readiness.candidate_qa_rows(rows, rd)], ["A-1"])

    def test_historical_matrix_pass_is_not_candidate_evidence(self):
        self.assertEqual(readiness.matrix_evidence_state("✅"), "none")

    def test_ui_suite_requires_all_four_successful_shards(self):
        jobs = [{"conclusion": "success"} for _ in range(4)]
        self.assertEqual(readiness.ui_suite_verdict(jobs, 10, 0), "pass")
        self.assertEqual(readiness.ui_suite_verdict(jobs[:3], 10, 0), "missing")

    def test_ui_suite_skipped_shard_cannot_be_hidden_by_other_passes(self):
        jobs = [{"conclusion": "success"} for _ in range(3)] + [{"conclusion": "skipped"}]
        self.assertEqual(readiness.ui_suite_verdict(jobs, 10, 0), "skipped")

    def test_ui_suite_failed_shard_cannot_be_hidden_by_other_passes(self):
        jobs = [{"conclusion": "success"} for _ in range(3)] + [{"conclusion": "failure"}]
        self.assertEqual(readiness.ui_suite_verdict(jobs, 10, 0), "fail")

    def test_manual_refresh_only_accepts_completed_main_build_ipa(self):
        base = {"name": "Build IPA", "head_branch": "main", "status": "completed",
                "head_sha": "abc", "id": 900, "run_number": 300}
        self.assertTrue(readiness.is_main_build_ipa_run(base))
        self.assertFalse(readiness.is_main_build_ipa_run({**base, "head_branch": "feature"}))
        self.assertFalse(readiness.is_main_build_ipa_run({**base, "name": "Compile check"}))
        self.assertFalse(readiness.is_main_build_ipa_run({**base, "status": "in_progress"}))




LINE = "Test Case '-[AteUITests.KeyFlowsQATests {}]' {} ({}.0 seconds)\n"
QA1 = readiness.QA1_REQUIRED_CASES


def qa_log(*entries):
    return "".join(LINE.format(name, result, secs) for name, result, secs in entries)


class QaFlowAggregationTests(unittest.TestCase):
    def results(self, text):
        return readiness.qa_flow_results(readiness.observe_qa_cases({}, text))

    def test_all_three_cases_pass(self):
        text = qa_log((QA1[0], "passed", 61), (QA1[1], "passed", 56), (QA1[2], "passed", 30))
        self.assertEqual(self.results(text)[1], "passed")

    def test_missing_one_case_fails(self):
        text = qa_log((QA1[0], "passed", 61), (QA1[1], "passed", 56))
        self.assertEqual(self.results(text)[1], "failed")

    def test_deprecated_or_wrong_name_never_counts(self):
        text = qa_log(("testQA1_AddFromURL", "passed", 200), (QA1[0], "passed", 61), (QA1[1], "passed", 56))
        self.assertEqual(self.results(text)[1], "failed")

    def test_zero_tests_yields_no_flow_result(self):
        self.assertEqual(self.results(""), {})

    def test_failure_is_sticky_against_later_pass(self):
        text = qa_log((QA1[0], "passed", 61), (QA1[1], "passed", 56),
                      (QA1[2], "failed", 240), (QA1[2], "passed", 30))
        self.assertEqual(self.results(text)[1], "failed")

    def test_failure_is_sticky_across_job_logs(self):
        cases = readiness.observe_qa_cases({}, qa_log((QA1[2], "failed", 240)))
        readiness.observe_qa_cases(cases, qa_log((QA1[0], "passed", 61), (QA1[1], "passed", 56), (QA1[2], "passed", 30)))
        self.assertEqual(readiness.qa_flow_results(cases)[1], "failed")


if __name__ == "__main__":
    unittest.main()
