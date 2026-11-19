"""Regression tests for secret handling in scripts/e2e/backend_e2e.py.

Covers CodeQL py/clear-text-logging-sensitive-data (the failure path now fails closed:
exception type name only) and py/redos (quoted-key/value redaction is a hand-written
linear scanner). scrub() is defence in depth on the pass path only.
Every secret in this file is a synthetic canary.
"""
import ast
import importlib.util
import io
import re
import sys
import time
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


class CanaryTestCase(unittest.TestCase):
    def setUp(self):
        self._saved = set(e2e._SENSITIVE_VALUES)
        self.addCleanup(self._restore_secrets)
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


class FailClosedTests(CanaryTestCase):
    def test_failure_logs_exception_type_name_only(self):
        def boom(_ctx):
            raise AssertionError(
                f"password grant 400 {{'error': 'invalid_grant', 'password': '{CANARY_PASSWORD}', "
                f"'service_key': '{CANARY_SERVICE_KEY}', 'access_token': '{CANARY_JWT}'}}")

        result, out, err = self.run_check(boom)
        self.assertEqual(result["status"], "fail")
        # Stored note: type name + check name + innermost frame location, never exception text.
        self.assertRegex(result["note"],
                         r"^AssertionError in boom at boom:\d+ " + re.escape(e2e._WITHHELD) + "$")
        # Console output is a static ids+status line - no flow from any source into the print sink.
        self.assertEqual(out, "❌ A-TEST-00: fail\n")
        self.assert_no_canaries(result["note"], out, err)
        self.assertNotIn("invalid_grant", out + err)  # no exception text anywhere
        self.assertEqual(err, "")  # no traceback on the failure path

    def test_source_line_secret_literal_never_logged(self):
        # Pre-fix leak shape: a secret literal on the raising line was printed by traceback.
        def boom(_ctx):
            inline = "zz-canary-password-9f8e7d6c5b"; raise RuntimeError(f"signup failed for {inline}")

        result, out, err = self.run_check(boom)
        self.assert_no_canaries(result["note"], out, err)
        self.assertEqual(out, "❌ A-TEST-00: fail\n")
        self.assertEqual(err, "")

    def test_fail_closed_boundary_logs_type_name_only(self):
        # The Ctx()/cleanup() boundary used by main() outside run_check.
        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit) as cm:
            e2e.fail_closed("e2e setup failed", RuntimeError(f"GET https://x/co?next={CANARY_PASSWORD} failed"))
        self.assertEqual(cm.exception.code, 1)
        self.assert_no_canaries(err.getvalue())
        self.assertIn("RuntimeError", err.getvalue())
        self.assertIn("withheld", err.getvalue())
        self.assertNotIn("Traceback", err.getvalue())


class PassPathScrubTests(CanaryTestCase):
    def test_passing_note_is_scrubbed_before_storage(self):
        def ok(_ctx):
            return f"published; service key was {CANARY_SERVICE_KEY}"

        result, out, err = self.run_check(ok)
        self.assertEqual(result["status"], "pass")
        self.assert_no_canaries(result["note"], out)
        self.assertIn("[redacted]", result["note"])
        self.assertEqual(out, "✅ A-TEST-00: pass\n")  # notes are stored/uploaded, never printed
        self.assertEqual(err, "")

    def test_note_is_capped_at_400_chars_after_redaction(self):
        def ok(_ctx):
            return "x" * 395 + CANARY_PASSWORD + "tail"

        result, out, _ = self.run_check(ok)
        self.assertLessEqual(len(result["note"]), 400)
        self.assertEqual(out, "✅ A-TEST-00: pass\n")
        self.assert_no_canaries(result["note"], out)
        # Redact-then-truncate: no partial canary may survive at the cut point.
        self.assertNotIn(CANARY_PASSWORD[:10], result["note"])

    def test_none_note_stays_clean(self):
        def ok(_ctx):
            return None

        result, out, _ = self.run_check(ok)
        self.assertEqual(result["note"], "")
        self.assertEqual(out, "✅ A-TEST-00: pass\n")


class ScrubUnitTests(unittest.TestCase):
    """Defence-in-depth scrub() on the pass path: patterns, scanner, variants."""

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

    def test_unregistered_jwt_shape_redacted(self):
        self.assertEqual(e2e.scrub(f"tok {CANARY_JWT} end"), "tok [redacted] end")

    def test_shape_patterns_run_before_registered_values(self):
        # A short registered vector inside a JWT must not split it and leave the tail logged.
        e2e.register_secret("abc", known_vector=True)
        jwt_with_vector = "eyJabcabcabc.zzzzabczz.abcabcabc"
        self.assertEqual(e2e.scrub(jwt_with_vector), "[redacted]")

    def test_json_and_dict_repr_password_fields_redacted(self):
        self.assertEqual(e2e.scrub('{"password": "hunter2"}'), '{"password": "[redacted]"}')
        self.assertEqual(e2e.scrub("{'password': 'hunter2'}"), "{'password': '[redacted]'}")
        self.assertEqual(
            e2e.scrub('{"refresh_token": "abc123def456"}'), '{"refresh_token": "[redacted]"}')

    def test_embedded_opposite_quote_fully_redacted(self):
        # Regression: a naive [^'"]* stop redacts only up to the opposite quote and leaks the tail.
        self.assertEqual(
            e2e.scrub("{'password': \"zz-canary'quote\"}"),
            "{'password': \"[redacted]\"}")

    def test_escaped_quote_inside_json_string_fully_redacted(self):
        self.assertEqual(
            e2e.scrub('{"password": "zz-canary-\\"escaped\\"-secret"}'),
            '{"password": "[redacted]"}')

    def test_unterminated_value_redacts_to_end(self):
        # Fail closed on malformed input rather than leaking a partial value.
        self.assertEqual(e2e.scrub('{"password": "abc'), '{"password": "[redacted]')

    def test_key_value_form_redacted(self):
        self.assertEqual(
            e2e.scrub("POST /auth/v1/token?access_token=abc123xyz&x=1"),
            "POST /auth/v1/token?access_token=[redacted]&x=1")

    def test_benign_text_survives(self):
        # 'password' as a value of an unrelated key and as a key prefix are not secrets.
        text = "grant_type=password password_min_length=8 two live sessions"
        self.assertEqual(e2e.scrub(text), text)
        self.assertEqual(e2e.scrub('say "monkey": "banana" ok'), 'say "monkey": "banana" ok')

    def test_short_values_are_not_blanket_registered(self):
        e2e.register_secret("zz9")  # below the 6-char floor: ignored
        self.assertEqual(e2e.scrub("code is zz9 ok"), "code is zz9 ok")

    def test_known_short_vector_is_redacted_when_flagged(self):
        # Mirrors t_auth02's intentional weak-password vectors ("abc", "onlyletters").
        e2e.register_secret("zz9", known_vector=True)
        self.assertEqual(e2e.scrub("code is zz9 ok"), "code is [redacted] ok")

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


class LinearTimeTests(unittest.TestCase):
    """py/redos and quadratic-scan regressions: matching and NON-matching quote-dense
    input must both be linear-time (a per-quote text.lower() once made this O(n^2))."""

    ADVERSARIES = {
        "all_backslashes_unterminated": '{"password": "' + "\\" * 100_000,
        "many_escaped_quotes": '{"password": "' + '\\"' * 20_000 + '"}',
        "mixed_quotes_and_escapes": '{"password": "' + "a'\\" * 20_000 + '"}',
        "long_values_repeated_pairs": ('{"password": "' + "a" * 100_000 + '"}') * 5,
        # Non-matching quote-dense input: the scanner probes every quote.
        "single_quotes_only": "'" * 80_000,
        "quoted_pairs_outside_keys": '"x"' * 50_000,
        "jwt_prefix_runs": "eyJ" * 30_000,
        "double_quotes_only": '"' * 80_000,
        "quote_backslash_mix": ("'\\" + '"\\') * 20_000,
        "near_miss_key_prefix": ('{"passwor": "x"} ') * 8_000,   # one char short of a key
        "near_miss_no_colon": ('"password" "password" ') * 8_000,
    }

    def test_adversarial_inputs_finish_fast(self):
        for name, adversary in self.ADVERSARIES.items():
            start = time.monotonic()
            e2e.scrub(adversary)
            elapsed = time.monotonic() - start
            self.assertLess(elapsed, 5.0, f"{name}: scrub took {elapsed:.2f}s on {len(adversary)} chars")

    def test_scaling_is_linear_on_quote_dense_input(self):
        # Doubling input size must roughly double time; quadratic gives ~4x per doubling.
        for base in ("'", '"', "'\\"):
            small, large = base * 40_000, base * 80_000
            e2e.scrub(small)  # warm-up
            samples = {"small": [], "large": []}
            # CPU time measures scanner work, not another job descheduling this process.
            # Alternate size order so warm caches/frequency changes do not always favour
            # the small input. Wall time remains an independent latency requirement.
            for sample in range(3):
                order = (("small", small), ("large", large))
                if sample % 2:
                    order = tuple(reversed(order))
                for name, text in order:
                    wall_start, cpu_start = time.monotonic(), time.process_time()
                    e2e.scrub(text)
                    elapsed = time.monotonic() - wall_start
                    samples[name].append(time.process_time() - cpu_start)
                    self.assertLess(elapsed, 5.0, f"{base!r}: {name} wall time {elapsed:.2f}s")
            t1 = min(samples["small"])
            t2 = min(samples["large"])
            self.assertLess(t2, 5.0, f"{base!r}: 80k chars took {t2:.2f}s CPU time")
            if t1 > 0.005:  # below timer noise the ratio is meaningless; the absolute bound covers it
                self.assertLess(t2 / t1, 3.0, f"{base!r}: 40k={t1:.3f}s 80k={t2:.3f}s looks super-linear")


    def test_adversarial_output_is_redacted(self):
        out = e2e.scrub('{"password": "' + '\\"' * 100 + 'tail"}')
        self.assertEqual(out, '{"password": "[redacted]"}')
        out = e2e.scrub('{"password": "' + "\\" * 100)
        self.assertEqual(out, '{"password": "[redacted]')


def _time(text):
    start = time.monotonic()
    e2e.scrub(text)
    return time.monotonic() - start


class PassNoteTaintTests(unittest.TestCase):
    """CodeQL taints values read under password-named keys (e.g. cfg.get("password_min_length")).
    Check-authored return notes must be constant text (comparison-derived constants allowed)."""

    @staticmethod
    def _returns(path, func_name):
        tree = ast.parse(Path(path).read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and node.name == func_name:
                return [n for n in ast.walk(node) if isinstance(n, ast.Return)]
        raise AssertionError(f"{func_name} not found in {path}")

    def test_auth02_note_is_constant(self):
        returns = self._returns(SCRIPT, "t_auth02")
        self.assertTrue(returns, "t_auth02 has no return statements")
        for ret in returns:
            self.assertIsInstance(ret.value, ast.Constant,
                                  "t_auth02's note must be a constant string (CodeQL name-taint)")

    def test_auth_settings_note_uses_no_config_names(self):
        returns = self._returns(SCRIPT.parent / "security_checks.py", "t_auth_settings")
        self.assertTrue(returns, "t_auth_settings has no return statements")
        for ret in returns:
            names = {n.id for n in ast.walk(ret) if isinstance(n, ast.Name)}
            self.assertFalse(names & {"cfg", "mn", "chars", "otp"},
                             f"t_auth_settings' note must not reference config reads: {names & {'cfg', 'mn', 'chars', 'otp'}}")


class ExplainableFailureTests(CanaryTestCase):
    def test_check_failure_records_status_and_whitelisted_key(self):
        self.assertTrue(issubclass(e2e.CheckFailure, AssertionError))

        def boom(_ctx):
            e2e.expect(False, "password grant", 400, {"error_code": "invalid_grant", "password": CANARY_PASSWORD})

        result, out, err = self.run_check(boom)
        self.assertEqual(result["status"], "fail")
        self.assertRegex(result["note"],
                         r"^CheckFailure in boom at boom:\d+: password grant HTTP 400 error_code=invalid_grant$")
        self.assertEqual(out, "\u274c A-TEST-00: fail\n")
        self.assertEqual(err, "")
        self.assert_no_canaries(result["note"], out, err)
        self.assertNotIn("'password'", result["note"])  # non-whitelisted keys never quoted

    def test_location_points_at_the_check_not_expect(self):
        def boom(_ctx):
            e2e.expect(False, "pull", 500)

        result, _, _ = self.run_check(boom)
        self.assertIn(" at boom:", result["note"])
        self.assertNotIn(" at expect:", result["note"])

    def test_only_closed_mapping_literals_are_recorded(self):
        self.assertEqual(e2e._KNOWN_ERROR_CODES, {
            "invalid_grant": "invalid_grant", "bad_request": "bad_request",
            "invalid_credentials": "invalid_credentials", "weak_password": "weak_password",
            "email_not_confirmed": "email_not_confirmed", "user_already_exists": "user_already_exists",
            "42501": "42501", "23505": "23505", "23503": "23503", "23502": "23502",
            "22p02": "22P02", "pgrst116": "PGRST116"})
        self.assertIsNone(e2e._error_code({"code": "unknown_code"}))

    def test_identifier_shaped_unregistered_credentials_are_omitted(self):
        canary = "canary-unregistered-credential-q7"
        self.assertNotIn(canary, e2e._SENSITIVE_VALUES)
        for key in ("error_code", "error", "code"):
            def boom(_ctx, key=key):
                e2e.expect(False, "publish", 400, {key: canary})
            result, out, err = self.run_check(boom)
            self.assertRegex(result["note"], r": publish HTTP 400$")
            self.assertNotIn(canary, result["note"] + out + err)

    def test_postgrest_code_works_with_canonical_case(self):
        for value in ("PGRST116", "pgrst116"):
            def boom(_ctx, value=value):
                e2e.expect(False, "pull", 406, {"code": value})
            result, _, _ = self.run_check(boom)
            self.assertRegex(result["note"], r": pull HTTP 406 code=PGRST116$")

    def test_free_form_keys_never_reach_the_note_unregistered_canary(self):
        # Unregistered, non-token-shaped prose credential: scrub cannot know it, so only the
        # strict identifier gate keeps it out of results.json / summary.md / qa_results.
        prose = "zzUNREGISTERED canary prose credential 9f8e7d6c5b"
        for key in ("message", "msg", "hint", "details", "error_description",
                    "error_code", "error", "code"):
            def boom(_ctx, key=key):
                e2e.expect(False, "publish", 400, {key: prose})

            result, _, _ = self.run_check(boom)
            self.assertRegex(result["note"], r"^CheckFailure in boom at boom:\d+: publish HTTP 400$", key)
            self.assertNotIn(prose, result["note"], key)
            self.assertNotIn(key + "=", result["note"], key)

    def test_valid_identifier_recorded_first_valid_key_wins(self):
        self.assertEqual(e2e._ERROR_KEYS, ("error_code", "error", "code"))

        def boom(_ctx):
            # An invalid value on the first key does not block a later valid identifier.
            e2e.expect(False, "publish", 400, {"error_code": "unknown_code", "error": "bad_request", "code": "42501"})

        result, _, _ = self.run_check(boom)
        self.assertIn("error=bad_request", result["note"])
        self.assertNotIn("error_code=", result["note"])
        self.assertNotIn("code=", result["note"])

    def test_non_dict_body_contributes_nothing(self):
        def boom(_ctx):
            e2e.expect(False, "RLS leak", 200, [{"data": "row-secret"}])

        result, _, _ = self.run_check(boom)
        self.assertRegex(result["note"], r": RLS leak HTTP 200$")
        self.assertNotIn("row-secret", result["note"])


    def test_unexpected_exceptions_still_fail_closed(self):
        def boom(_ctx):
            raise ValueError(f"token {CANARY_SERVICE_KEY}")

        result, out, err = self.run_check(boom)
        self.assertRegex(result["note"], r"^ValueError in boom at boom:\d+ " + re.escape(e2e._WITHHELD) + "$")
        self.assert_no_canaries(result["note"], out, err)


class CallSitePinTests(unittest.TestCase):
    def test_every_http_status_assert_uses_expect(self):
        src = SCRIPT.read_text()
        # The only remaining plain `assert code` is the Ctx.__init__ api-keys boundary, which
        # must keep failing closed: it runs before any check and can echo credentials.
        self.assertEqual(src.count("assert code"), 1)
        self.assertIn('assert code == 200, f"api-keys {code}"', src)
        sec = (SCRIPT.parent / "security_checks.py").read_text()
        self.assertNotIn("assert code", sec)
        self.assertIn("from backend_e2e import http, URL, REF, upsert, expect", sec)


class ModuleIdentityTests(unittest.TestCase):
    def test_script_mode_alias_is_module_level_before_any_import_use(self):
        src = SCRIPT.read_text()
        alias = 'sys.modules.setdefault("backend_e2e", sys.modules[__name__])'
        self.assertIn(alias, src)
        self.assertLess(src.index(alias), src.index("import security_checks"))
        self.assertLess(src.index(alias), src.index("def http("))

    def test_script_mode_shares_one_checkfailure_identity(self):
        # No live calls: the script is exec'd as __main__ with the management token absent
        # and a clean argv; main() dies at Ctx construction, before any network. The alias
        # and the security_checks import chain must already give one module identity.
        import subprocess
        harness = (
            "import importlib.util, os, sys\n"
            "os.environ.pop('SUPABASE_ACCESS_TOKEN', None)\n"
            "sys.argv = ['backend_e2e.py']\n"
            f"spec = importlib.util.spec_from_file_location('__main__', r'{SCRIPT}')\n"
            "m = importlib.util.module_from_spec(spec)\n"
            "sys.modules['__main__'] = m\n"
            "try:\n"
            "    spec.loader.exec_module(m)\n"
            "except BaseException:\n"
            "    pass\n"
            "import security_checks as sc\n"
            "bm = sys.modules.get('backend_e2e')\n"
            "print('ALIAS', bm is m)\n"
            "print('SHARED', sc.expect is m.expect and sc.expect.__module__ == '__main__')\n"
        )
        proc = subprocess.run([sys.executable, "-c", harness], capture_output=True, text=True,
                              cwd=str(SCRIPT.parent), timeout=60)
        self.assertIn("ALIAS True", proc.stdout, proc.stderr[-500:])
        self.assertIn("SHARED True", proc.stdout, proc.stderr[-500:])


class CollectionTests(unittest.TestCase):
    def test_all_defined_tests_are_collected(self):
        # Guards against tests silently nested inside another def (a past bug here).
        defined = sum(1 for line in open(__file__) if line.strip().startswith("def test_"))
        collected = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]).countTestCases()
        self.assertEqual(defined, collected)


if __name__ == "__main__":
    unittest.main()
