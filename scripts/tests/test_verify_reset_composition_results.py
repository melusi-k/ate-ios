import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-reset-composition-results.py'
spec = importlib.util.spec_from_file_location('reset_results', SCRIPT)
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)


def fixture(sentinel='** TEST EXECUTE SUCCEEDED **'):
    lines = ['Command line invocation:',
             '/Applications/Xcode.app/usr/bin/xcodebuild test-without-building '
             + ' '.join('-only-testing:AteTests/' + name for name in parser.EXPECTED)
             + ' -resultBundlePath /tmp/reset-composition.xcresult',
             "Test Suite 'Selected tests' started at 2026-11-08 00:46:27.004.",
             "Test Suite 'AteTests.xctest' started at 2026-11-08 00:46:27.004."]
    for name, methods in parser.EXPECTED.items():
        lines.append(f"Test Suite '{name}' started at 2026-11-08 00:46:27.004.")
        for method in methods:
            lines.extend([f"Test Case '-[AteTests.{name} {method}]' started.",
                          f"Test Case '-[AteTests.{name} {method}]' passed (0.000 seconds)."])
        lines.extend([f"Test Suite '{name}' passed at 2026-11-08 00:46:27.949.",
                      f' Executed {len(methods)} tests, with 0 failures (0 unexpected) in 0.006 (0.079) seconds'])
    lines.extend(["Test Suite 'AteTests.xctest' passed at 2026-11-08 00:46:27.949.",
                  ' Executed 68 tests, with 0 failures (0 unexpected) in 0.676 (0.945) seconds',
                  "Test Suite 'Selected tests' passed at 2026-11-08 00:46:27.949.",
                  ' Executed 68 tests, with 0 failures (0 unexpected) in 0.676 (0.946) seconds',
                  sentinel])
    return '\n'.join(lines)


class ResetResultEvidenceTests(unittest.TestCase):
    def rejects(self, text):
        with self.assertRaises(ValueError):
            parser.validate(text)

    def test_both_success_spellings_accept_rounded_zero_methods(self):
        self.assertEqual(sum(map(len, parser.EXPECTED.values())), 68)
        for marker in parser.SUCCESS:
            with self.subTest(marker=marker):
                self.assertEqual(set(parser.validate(fixture(marker))), set(parser.EXPECTED))

    def test_complete_sentinel_not_substring(self):
        for marker in ['prefix ** TEST EXECUTE SUCCEEDED **', '** TEST EXECUTE SUCCEEDED ** suffix',
                       'TEST EXECUTE SUCCEEDED', '** TEST EXECUTE SUCCEEDED ***', '']:
            with self.subTest(marker=marker): self.rejects(fixture(marker))

    def test_failure_alone_or_with_success_anywhere(self):
        for failure in parser.FAILURE:
            for success in parser.SUCCESS:
                for text in [fixture(failure), failure + '\n' + fixture(success),
                             fixture(success) + '\n' + failure]:
                    with self.subTest(failure=failure, success=success): self.rejects(text)

    def test_method_missing_duplicate_unexpected_skipped_failed_malformed(self):
        text = fixture()
        passed = next(line for line in text.splitlines() if "Test Case '" in line and 'passed (' in line)
        start = passed.split(" passed (")[0] + ' started.'
        variants = [text.replace(passed, ''), text.replace(passed, passed + '\n' + passed),
                    text.replace(start, start + '\n' + start),
                    text.replace(passed, passed.replace('testJournalClearsInvalidFutureRowsAndOrphanPayloads', 'testUnexpected')),
                    text.replace(passed, passed.replace('passed (0.000 seconds)', 'skipped (0.000 seconds)')),
                    text.replace(passed, passed.replace('passed (0.000 seconds)', 'failed (0.000 seconds)')),
                    text.replace(passed, passed.replace('0.000', 'NaN')),
                    text.replace(passed, passed.replace('AteTests.', 'OtherTests.')),
                    text.replace(start, '')]
        for index, variant in enumerate(variants):
            with self.subTest(index=index): self.rejects(variant)

    def test_suite_duration_missing_zero_malformed_nonfinite(self):
        text = fixture()
        summary = ' Executed 6 tests, with 0 failures (0 unexpected) in 0.006 (0.079) seconds'
        for replacement in ['', summary.replace('0.006', '0.000'), summary.replace('0.079', '0.000'),
                            summary.replace('0.006', 'NaN'), summary.replace('0.006', 'inf'),
                            summary.replace('0.006', '-1.0'), summary.replace('0.006', 'bogus'),
                            summary.replace('0.006', '9' * 400),
                            summary.replace('6 tests', '5 tests'), summary.replace('0 failures', '1 failures')]:
            with self.subTest(replacement=replacement): self.rejects(text.replace(summary, replacement, 1))

    def test_outer_suite_cannot_supply_missing_expected_summary(self):
        text = fixture()
        summary = ' Executed 6 tests, with 0 failures (0 unexpected) in 0.006 (0.079) seconds'
        self.rejects(text.replace(summary, "Test Suite 'AteTests.xctest' passed at 2026-11-08 00:46:27.949.\n" + summary, 1))

    def test_wrapper_summaries_and_completions_are_required(self):
        text = fixture()
        wrapper_summary = ' Executed 68 tests, with 0 failures (0 unexpected) in 0.676 (0.945) seconds'
        selected_summary = ' Executed 68 tests, with 0 failures (0 unexpected) in 0.676 (0.946) seconds'
        wrapper_completion = "Test Suite 'AteTests.xctest' passed at 2026-11-08 00:46:27.949."
        for variant in [text.replace(wrapper_summary, wrapper_summary.replace('0 failures', '1 failures')),
                        text + '\nExecuted 1 test, with 1 failures',
                        text.replace(wrapper_completion, ''),
                        text.replace(selected_summary, ''),
                        text.replace(wrapper_summary, ''),
                        text.replace(wrapper_summary, wrapper_summary + '\n' + wrapper_summary),
                        text.replace(selected_summary, selected_summary + '\n' + selected_summary),
                        text.replace(wrapper_summary, wrapper_summary.replace('68 tests', '67 tests')),
                        text.replace(wrapper_summary, wrapper_summary.replace('0.676', 'NaN')),
                        text.replace("Test Suite 'AteTests.xctest' started at 2026-11-08 00:46:27.004.", '')]:
            with self.subTest(variant=variant[-160:]): self.rejects(variant)

    def test_wrong_invocation_duplicate_restart_missing_suite_fail_closed(self):
        text = fixture()
        for variant in [text + '\n' + text, text.replace('test-without-building', 'build'),
                        text.replace('reset-composition.xcresult', 'other.xcresult'),
                        text.replace('-resultBundlePath', '-skip-testing:AteTests -resultBundlePath'),
                        text.replace('-only-testing:AteTests/ClearAllLocalDataTests ', ''),
                        text.replace('Command line invocation:', 'Command invocation:'),
                        text.replace("Test Suite 'Selected tests' started", "Test Suite 'Other tests' started"),
                        text.replace("Test Suite 'Selected tests' passed", "Test Suite 'Other tests' passed"),
                        text + '\nRestarting after unexpected exit',
                        text.replace("Test Suite 'ClearAllLocalDataTests' passed", "Test Suite 'ClearAllLocalDataTests' failed"),
                        text.replace('** TEST EXECUTE SUCCEEDED **', '** TEST EXECUTE SUCCEEDED **\n** TEST SUCCEEDED **')]:
            with self.subTest(variant=variant[-120:]): self.rejects(variant)


if __name__ == '__main__':
    unittest.main()
