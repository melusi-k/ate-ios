import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bound-release-body.py"
spec = importlib.util.spec_from_file_location("bound_release_body", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BoundReleaseBodyTests(unittest.TestCase):
    def test_short_body_is_exact(self):
        text = "## Build 442\nSource 6f9fe56\nInstall unsigned\nSHA abc\nNot qualified\n"
        self.assertEqual(module.bounded_body(text), text)

    def test_exact_ceiling_is_not_trimmed(self):
        text = "x" * module.MAX_BYTES
        self.assertEqual(module.bounded_body(text), text)

    def test_oversize_retains_start_and_footer_with_notice(self):
        start = "## Build 442\nSource 6f9fe56\n"
        footer = "\nInstall unsigned\nSHA abc\nNot qualified\n"
        result = module.bounded_body(start + "history\n" * 30000 + footer)
        self.assertTrue(result.startswith(start))
        self.assertTrue(result.endswith(footer))
        self.assertIn("Middle of source history omitted", result)
        self.assertLessEqual(len(result.encode("utf-8")), module.MAX_BYTES)

    def test_unicode_boundaries_remain_valid(self):
        result = module.bounded_body("🍲é" * 50000 + "\nSHA footer\n")
        self.assertEqual(result.encode("utf-8").decode("utf-8"), result)
        self.assertNotIn("\ufffd", result)
        self.assertLessEqual(len(result.encode("utf-8")), module.MAX_BYTES)
        self.assertTrue(result.endswith("\nSHA footer\n"))

    def test_workflow_caps_both_release_calls_and_does_not_hide_create_errors(self):
        workflow = SCRIPT.parents[1] / ".github/workflows/build-ipa.yml"
        text = workflow.read_text()
        self.assertIn('cat build/notes.md >> "$GITHUB_STEP_SUMMARY"', text)
        self.assertIn('python3 scripts/bound-release-body.py build/notes.md build/release-body.md', text)
        self.assertEqual(text.count('--notes-file build/release-body.md'), 2)
        self.assertNotIn('|| echo "$TAG already exists', text)
        self.assertIn('if gh release view "$TAG" --json url', text)

    def run_release_block(self, existing, create_status):
        import os
        import subprocess
        import tempfile
        text = (SCRIPT.parents[1] / ".github/workflows/build-ipa.yml").read_text()
        start = text.index('          if gh release view "$TAG"')
        end = text.index('          # Rolling latest-build:', start)
        block = "\n".join(line[10:] for line in text[start:end].splitlines())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "build").mkdir()
            gh = root / "gh"
            gh.write_text('#!/bin/bash\nif [ "$2" = view ]; then exit "$EXISTING_STATUS"; fi\n'
                          'echo "CREATE_CALLED"\necho "actual create error" >&2\nexit "$CREATE_STATUS"\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       EXISTING_STATUS="0" if existing else "1", CREATE_STATUS=str(create_status),
                       TAG="build-442-Production", IPA_NAME="fixture.ipa", APP_VERSION="0.1.442",
                       BUILD_NUMBER="442", CH_TITLE="", GITHUB_SHA="6f9fe56" + "0" * 33)
            return subprocess.run(["bash", "-e", "-c", block], cwd=root, env=env,
                                  text=True, capture_output=True)

    def test_create_failure_stays_failure_and_not_already_exists(self):
        result = self.run_release_block(False, 42)
        self.assertEqual(result.returncode, 42)
        self.assertIn("actual create error", result.stderr)
        self.assertNotIn("already exists", result.stdout)

    def test_existing_release_is_not_recreated(self):
        result = self.run_release_block(True, 42)
        self.assertEqual(result.returncode, 0)
        self.assertIn("release already exists", result.stdout)
        self.assertNotIn("CREATE_CALLED", result.stdout)
