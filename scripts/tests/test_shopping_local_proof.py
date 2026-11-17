from pathlib import Path
import importlib.util
import unittest
from unittest.mock import patch
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT/'scripts/e2e/shopping_local_proof.py'
spec = importlib.util.spec_from_file_location('shopping_local_proof', SCRIPT)
proof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)

class ShoppingLocalSafetyTests(unittest.TestCase):
    def status(self):
        return {'API_URL': 'http://127.0.0.1:54321',
                'DB_URL': 'postgresql://postgres:fixture@127.0.0.1:54322/postgres',
                'ANON_KEY': 'fixture-anon', 'SERVICE_ROLE_KEY': 'fixture-service'}
    def test_only_literal_loopback_origin_and_database_are_accepted(self):
        instance = proof.LocalProof(self.status())
        self.assertEqual(instance.api.hostname, '127.0.0.1')
        self.assertEqual(proof.loopback_url('http://[::1]:54321', {'http'}).hostname, '::1')
        for bad in ['http://project.supabase.co:54321', 'http://localhost:54321',
                    'http://127.0.0.1.attacker.invalid:54321', 'http://192.168.1.1:54321',
                    'http://169.254.169.254:54321', 'http://0.0.0.0:54321',
                    'http://127.0.0.1:54321?host=external', 'http://127.0.0.1:54321#external',
                    'https://127.0.0.1:54321', 'http://127.0.0.1']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                status = self.status(); status['API_URL'] = bad; proof.LocalProof(status)
        for bad in ['postgresql://postgres:fixture@db.project.supabase.co:5432/postgres',
                    'postgresql://postgres:fixture@127.0.0.1:54322/postgres?hostaddr=8.8.8.8',
                    'postgresql://postgres:fixture@127.0.0.1:54322/production']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                status = self.status(); status['DB_URL'] = bad; proof.LocalProof(status)
    def test_redirects_fail_closed_without_forwarding_auth(self):
        request = urllib.request.Request('http://127.0.0.1:54321', headers={'Authorization':'Bearer fixture'})
        with self.assertRaises(ValueError):
            proof.NoRedirect().redirect_request(request, None, 302, 'redirect', {}, 'https://elsewhere.invalid')
    def test_guarded_client_has_no_hosted_or_proxy_fallback(self):
        source = SCRIPT.read_text()
        self.assertIn('urllib.request.ProxyHandler({})', source)
        self.assertIn('hostaddr=self.db.hostname', source)
        self.assertIn('select purpose from public.ate501_disposable', source)
        self.assertIn("select count(*) from auth.users", source)
        for token in ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_PROJECT_REF', 'supabase.co', 'db push', 'print(e)', 'traceback']:
            self.assertNotIn(token, source)
    def test_proof_requires_real_lock_and_negative_overwrite_not_just_exception(self):
        source = SCRIPT.read_text()
        for token in ['set local role authenticated', 'pg_stat_activity', "state[0] == 'Lock'", 'assert blocked',
                      'newer-first-stale-second-real-lock', 'stale-first-newer-second-real-lock',
                      'equal-tombstone-first-committer-wins', 'equal-live-first-committer-wins',
                      'postgrest-conflict-parity-and-two-user-rls', 'guard-restored-rejects-stale',
                      'disable trigger shopping_preserve_newer_sync', 'enable trigger shopping_preserve_newer_sync',
                      'self.race(user, (200,False), (100,False), (100,False))']:
            self.assertIn(token, source)
    def test_workflow_manual_no_secrets_and_never_hosted_migrations(self):
        source = (ROOT/'.github/workflows/shopping-local-proof.yml').read_text()
        for token in ['workflow_dispatch:', 'ubuntu-latest', 'supabase@3.2.0', 'psycopg[binary]==3.3.9',
                      'stop --workdir', '--no-backup', 'candidate', 'if: always()']:
            if token != 'candidate': self.assertIn(token, source)
        for token in ['secrets.', 'backend_e2e.py', 'db push', 'link --project', 'pull_request:', 'push:']:
            self.assertNotIn(token, source)
        artifact = source.split('path: ${{ runner.temp }}/ate501-proof.json',1)
        self.assertEqual(len(artifact),2)
        self.assertNotIn('path: ${{ runner.temp }}/*', source)
        config = (ROOT/'scripts/e2e/shopping-local/supabase/config.toml').read_text()
        self.assertIn('project_id = "ate-shopping-501-local"', config)
        self.assertIn('enable_anonymous_sign_ins = false', config)
