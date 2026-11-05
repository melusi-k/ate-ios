"""Regression tests for secret redaction in scripts/e2e/backend_e2e.py.

Covers CodeQL py/clear-text-logging-sensitive-data (alert: run() printed the raw
exception note and traceback). Every secret in this file is a synthetic canary.
"""
import importlib.util
import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "e2e" / "backend_e2e.py"
SPEC = importlib.util.spec_from_file_location("backend_e2e", SCRIPT)
e2e = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(e2e)

# Synthetic canaries - never real credentials.
CANARY_PASSWORD = "zz-canary-password-9f8e7d6c5b"
CANARY_SERVICE_KEY = "zz-canary-service-role-key-1a2b3c4d5e6f"
CANARY_JWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjYW5hcnktdGVzdCJ9.zzcanarysignature"
CANARIES = (CANARY_PASSWORD, CANARY_SERVICE_KEY, CANARY_JWT)


class RunCheckRedactionTests(unittest.TestCase):
    def setUp(self):
        self._saved = set(e2e._SENSITIVE_VALUES)
        self.addCleanup(self._restore_secrets)
        # Passwords and non-JWT keys are redacted only once registered.
        e2e.register_secret(CANARY_PASSWORD)
        e2e.register_secret(CANARY_SERVICE_KEY)

    def _restore_secrets(self):
        e2e._SENSITIVE_VALUES.clear()
        e2e._SENSITIVE_VALUES.update(self._saved)

    def run_check(self, fn):
        results, out, err = {}, io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            e2e.run_check(None, results, ["A-TEST-00"], fn)
        return results["A-TEST-00"], out.getvalue(), err.getvalue()

    def assert_no_canaries(self, *texts):
        for text in texts:
            for canary in CANARIES:
                self.assertNotIn(canary, text)

    def test_failing_check_never_logs_canaries(self):
        def boom(_ctx):
            raise AssertionError(
                f"password grant 400 {{'error': 'invalid_grant', 'password': '{CANARY_PASSWORD}', "
                f"'service_key': '{CANARY_SERVICE_KEY}', 'access_token': '{CANARY_JWT}'}}")

        result, out, err = self.run_check(boom)
        self.assertEqual(result["status"], "fail")
        self.assert_no_canaries(result["note"], out, err)
        self.assertIn("[redacted]", result["note"])
        # Traceback is still emitted for debugging, but scrubbed.
        self.assertIn("Traceback", err)
        self.assertIn("[redacted]", err)

    def test_traceback_source_line_literal_is_scrubbed(self):
        # Mirrors backend_e2e.py's pre-fix leak: a secret literal on the raising line
        # used to be printed verbatim by traceback.print_exc().
        def boom(_ctx):
            inline = "zz-canary-password-9f8e7d6c5b"; raise RuntimeError(f"signup failed for {inline}")

        result, out, err = self.run_check(boom)
        self.assert_no_canaries(result["note"], out, err)

    def test_passing_note_is_scrubbed_before_storage(self):
        def ok(_ctx):
            return f"published; service key was {CANARY_SERVICE_KEY}"

        result, out, err = self.run_check(ok)
        self.assertEqual(result["status"], "pass")
        self.assert_no_canaries(result["note"], out)
        self.assertIn("[redacted]", result["note"])
        self.assertEqual(err, "")

    def test_note_is_capped_at_400_chars_after_redaction(self):
        def boom(_ctx):
            raise AssertionError("x" * 395 + CANARY_PASSWORD + "tail")

        result, out, err = self.run_check(boom)
        self.assertLessEqual(len(result["note"]), 400)
        self.assert_no_canaries(result["note"], out, err)
        # Redact-then-truncate: no partial canary may survive at the cut point.
        self.assertNotIn(CANARY_PASSWORD[:10], result["note"])

    def test_fail_closed_boundary_scrubs_and_exits(self):
        # The Ctx()/cleanup() boundary used by main() outside run_check.
        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit) as cm:
            e2e.fail_closed("e2e setup failed", RuntimeError(f"GET https://x/co?next={CANARY_PASSWORD} failed"))
        self.assertEqual(cm.exception.code, 1)
        self.assert_no_canaries(err.getvalue())
        self.assertIn("[redacted]", err.getvalue())
        self.assertLessEqual(len(err.getvalue()), 401)  # 400-char cap + newline
        self.assertNotIn("Traceback", err.getvalue())

    def test_traceback_is_bounded(self):
        def boom(_ctx):
            raise AssertionError("y" * 10000)

        _, _, err = self.run_check(boom)
        self.assertIn("[traceback truncated]", err)
        self.assertLessEqual(len(err), e2e._MAX_TRACEBACK + 40)

    def test_none_note_stays_clean(self):
        def ok(_ctx):
            return None

        result, out, _ = self.run_check(ok)
        self.assertEqual(result["note"], "")
        self.assertNotIn("None", out)

    def test_unregistered_jwt_shape_is_redacted_by_pattern(self):
        # CANARY_JWT is never registered; the JWT pattern must catch it.
        def boom(_ctx):
            raise AssertionError(f"upstream echoed {CANARY_JWT}")

        result, out, err = self.run_check(boom)
        self.assert_no_canaries(result["note"], out, err)


class ScrubUnitTests(unittest.TestCase):
    def setUp(self):
        self._saved = set(e2e._SENSITIVE_VALUES)
        self.addCleanup(self._restore_secrets)
        e2e._SENSITIVE_VALUES.clear()

    def _restore_secrets(self):
        e2e._SENSITIVE_VALUES.clear()
        e2e._SENSITIVE_VALUES.update(self._saved)

    def test_bearer_token_redacted(self):
        self.assertEqual(
            e2e.scrub(f"Authorization: Bearer {CANARY_SERVICE_KEY}"),
            "Authorization: Bearer [redacted]")

    def test_json_and_dict_repr_password_fields_redacted(self):
        self.assertEqual(e2e.scrub('{"password": "hunter2"}'), '{"password": "[redacted]"}')
        self.assertEqual(e2e.scrub("{'password': 'hunter2'}"), "{'password': '[redacted]'}")
        self.assertEqual(
            e2e.scrub('{"refresh_token": "abc123def456"}'), '{"refresh_token": "[redacted]"}')

    def test_key_value_form_redacted(self):
        self.assertEqual(
            e2e.scrub("POST /auth/v1/token?access_token=abc123xyz&x=1"),
            "POST /auth/v1/token?access_token=[redacted]&x=1")

    def test_benign_text_survives(self):
        # 'password' as a value of an unrelated key and as a key prefix are not secrets.
        text = "grant_type=password password_min_length=8 two live sessions"
        self.assertEqual(e2e.scrub(text), text)

    def test_short_values_are_not_blanket_registered(self):
        e2e.register_secret("zz9")  # below the 6-char floor: ignored
        self.assertEqual(e2e.scrub("code is zz9 ok"), "code is zz9 ok")

    def test_known_short_vector_is_redacted_when_flagged(self):
        # Mirrors t_auth02's intentional weak-password vectors ("abc", "onlyletters").
        e2e.register_secret("zz9", known_vector=True)
        self.assertEqual(e2e.scrub("code is zz9 ok"), "code is [redacted] ok")

    def test_embedded_opposite_quote_fully_redacted(self):
        # Regression: the old pattern stopped at the opposite quote and leaked the tail.
        self.assertEqual(
            e2e.scrub("{'password': \"zz-canary'quote\"}"),
            "{'password': \"[redacted]\"}")

    def test_escaped_quote_inside_json_string_fully_redacted(self):
        self.assertEqual(
            e2e.scrub('{"password": "zz-canary-\\"escaped\\"-secret"}'),
            '{"password": "[redacted]"}')

    def test_registered_secret_matches_json_escaped_form(self):
        canary = 'zz-canary-"quoted"-secret'
        e2e.register_secret(canary)
        self.assertEqual(
            e2e.scrub('{"note": "zz-canary-\\"quoted\\"-secret"}'),
            '{"note": "[redacted]"}')

    def test_registered_secret_matches_url_encoded_forms(self):
        canary = "zz canary/pass:?123"
        e2e.register_secret(canary)
        self.assertEqual(e2e.scrub("next=zz+canary%2Fpass%3A%3F123"), "next=[redacted]")
        self.assertEqual(e2e.scrub("next=zz%20canary%2Fpass%3A%3F123"), "next=[redacted]")

    def test_longest_registered_value_wins(self):
        e2e.register_secret("zz-canary-token-123")
        e2e.register_secret("zz-canary-token-123-extended")
        self.assertEqual(
            e2e.scrub("key is zz-canary-token-123-extended ok"),
            "key is [redacted] ok")


if __name__ == "__main__":
    unittest.main()
