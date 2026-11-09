"""Regression checks for the QA key-flow aggregation contract.

QA1 runs as three independent named cases; the flow may pass only when all three
exact case names passed. A failure is sticky: no later pass may launder it.
"""
import importlib.util
import pathlib
import re
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "qa-summary.py"
SPEC = importlib.util.spec_from_file_location("qa_summary", SCRIPT)
qa_summary = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(qa_summary)

LINE = "Test Case '-[AteUITests.KeyFlowsQATests {}]' {} ({}.0 seconds)\n"
QA1 = qa_summary.QA1_REQUIRED_CASES


def log(*entries):
    return "".join(LINE.format(name, result, secs) for name, result, secs in entries)


class WorkflowCaseListContractTests(unittest.TestCase):
    """The workflow's -only-testing QA1 list must be exactly the required case names;
    a comment or edit that breaks the command or drops a case must fail here."""

    def test_workflow_qa1_only_testing_names_equal_required_cases(self):
        workflow = (pathlib.Path(__file__).resolve().parents[2]
                    / ".github" / "workflows" / "dogfood-qualification.yml").read_text()
        listed = re.findall(r"-only-testing:AteUITests/KeyFlowsQATests/(testQA1_\w+)", workflow)
        self.assertEqual(sorted(listed), sorted(qa_summary.QA1_REQUIRED_CASES))
        self.assertEqual(len(listed), 3)

    def test_readiness_required_cases_match(self):
        readiness_spec = importlib.util.spec_from_file_location(
            "readiness", pathlib.Path(__file__).resolve().parents[1] / "release" / "readiness.py")
        readiness = importlib.util.module_from_spec(readiness_spec)
        readiness_spec.loader.exec_module(readiness)
        self.assertEqual(readiness.QA1_REQUIRED_CASES, qa_summary.QA1_REQUIRED_CASES)


class QaSummaryAggregationTests(unittest.TestCase):
    def state(self, text):
        return qa_summary.flow_state(1, qa_summary.parse_cases(text).get(1, {}))

    def test_all_three_cases_pass(self):
        text = log((QA1[0], "passed", 61), (QA1[1], "passed", 56), (QA1[2], "passed", 30))
        self.assertEqual(self.state(text)[0], "passed")
        self.assertIn("✅ pass (3/3 cases)", qa_summary.render(qa_summary.parse_cases(text)))

    def test_missing_one_case_fails(self):
        text = log((QA1[0], "passed", 61), (QA1[1], "passed", 56))
        state, observed, need = self.state(text)
        self.assertEqual((state, observed, need), ("failed", 2, 3))

    def test_deprecated_or_wrong_name_never_counts(self):
        text = log(("testQA1_AddFromURL", "passed", 200), (QA1[0], "passed", 61), (QA1[1], "passed", 56))
        state, observed, _ = self.state(text)
        self.assertEqual(state, "failed")
        self.assertEqual(observed, 2)  # only exact case names count

    def test_zero_tests_is_not_run_not_pass(self):
        cases = qa_summary.parse_cases("")
        self.assertEqual(qa_summary.flow_state(1, cases.get(1, {}))[0], "not run")
        self.assertIn("**0/8 key flows passed.**", qa_summary.render(cases))

    def test_failure_is_sticky_against_later_pass(self):
        text = log((QA1[0], "passed", 61), (QA1[1], "passed", 56),
                   (QA1[2], "failed", 240), (QA1[2], "passed", 30))
        self.assertEqual(self.state(text)[0], "failed")

    def test_other_flows_still_pass_on_a_single_case(self):
        text = log(("testQA4_Save", "passed", 48))
        self.assertEqual(qa_summary.flow_state(4, qa_summary.parse_cases(text).get(4, {}))[0], "passed")


if __name__ == "__main__":
    unittest.main()
