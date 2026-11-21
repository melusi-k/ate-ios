#!/usr/bin/env python3
"""Disposable local Supabase proof only. Never use the hosted backend E2E route.

Accepts local CLI status JSON from an explicitly started local stack. Refuses DNS,
non-loopback IPs, proxies, redirects and connection query parameters before I/O.
Prints only static check names/statuses; no exception, user/token or DB URL output.
"""
import argparse
import concurrent.futures
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]


def loopback_url(value, schemes):
    u = urllib.parse.urlsplit(value)
    if u.scheme not in schemes or not u.hostname or u.query or u.fragment:
        raise ValueError('Local endpoint required')
    # No DNS, including localhost aliases. Only literal loopback addresses.
    if not ipaddress.ip_address(u.hostname).is_loopback:
        raise ValueError('Local endpoint required')
    if not u.port:
        raise ValueError('Explicit local port required')
    return u


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Redirect forbidden')


class LocalProof:
    def __init__(self, status):
        self.api = loopback_url(status['API_URL'], {'http'} )
        self.db = loopback_url(status['DB_URL'], {'postgresql', 'postgres'})
        if self.api.username or self.api.password or self.api.path not in ('', '/'):
            raise ValueError('Plain local API origin required')
        if not self.db.username or not self.db.password or self.db.path != '/postgres':
            raise ValueError('Disposable local database required')
        self.anon = status['ANON_KEY']
        self.service = status['SERVICE_ROLE_KEY']
        if not self.anon or not self.service:
            raise ValueError('Local keys required')
        self.http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self.users = []
        self.results = []

    def connect(self, user=None, app='ate501-observer'):
        import psycopg
        # Do not pass the original DSN through. No environment-supplied hostaddr/service/options.
        c = psycopg.connect(host=self.db.hostname, hostaddr=self.db.hostname, port=self.db.port,
                             user=urllib.parse.unquote(self.db.username),
                             password=urllib.parse.unquote(self.db.password), dbname='postgres',
                             connect_timeout=5, application_name=app, sslmode='disable',
                             options='-c statement_timeout=10000 -c lock_timeout=8000')
        if user:
            c.execute('set local role authenticated')
            c.execute("select set_config('request.jwt.claim.sub', %s, true)", (user,))
            c.execute("select set_config('request.jwt.claims', %s, true)",
                      (json.dumps({'sub': user, 'role': 'authenticated'}),))
        return c

    def request(self, method, path, token=None, body=None, service=False):
        key = self.service if service else self.anon
        headers = {'apikey': key, 'Authorization': 'Bearer ' + (token or key)}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        if path.startswith('/rest/') and method == 'POST':
            headers['Prefer'] = 'resolution=merge-duplicates,return=representation'
        request = urllib.request.Request(self.api.geturl().rstrip('/') + path,
            data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
        try:
            with self.http.open(request, timeout=10) as response:
                return response.status, json.loads(response.read() or b'null')
        except urllib.error.HTTPError as e:
            return e.code, None

    def create_user(self):
        email = 'shopping501-' + uuid.uuid4().hex + '@example.invalid'
        password = uuid.uuid4().hex + uuid.uuid4().hex
        code, value = self.request('POST', '/auth/v1/admin/users', service=True,
            body={'email': email, 'password': password, 'email_confirm': True})
        assert code in (200, 201)
        user = value['id']; self.users.append(user)
        code, value = self.request('POST', '/auth/v1/token?grant_type=password',
                                   body={'email': email, 'password': password})
        assert code == 200 and value['user']['id'] == user
        return user, value['access_token']

    @staticmethod
    def upsert(c, user, item, stamp, deleted=False):
        c.execute('''insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted)
            values(%s,'shopping',%s,%s::jsonb,%s,%s)
            on conflict(user_id,kind,id) do update set data=excluded.data,
              updated_at=excluded.updated_at, deleted=excluded.deleted''',
            (user, item, json.dumps({'name': 'fixture', 'stamp': stamp}), stamp, deleted))

    def row(self, user, item):
        with self.connect(user) as c:
            return c.execute("select updated_at,deleted from public.user_recipes where user_id=%s and kind='shopping' and id=%s", (user, item)).fetchone()

    def race(self, user, first, second, expected):
        item = uuid.uuid4().hex
        with self.connect(user) as seed:
            self.upsert(seed, user, item, 1)
        # First authenticated transaction holds the actual conflict row lock.
        owner = self.connect(user)
        tag = 'ate501-waiter-' + uuid.uuid4().hex[:10]
        ready = threading.Event()
        def waiter():
            with self.connect(user, tag) as c:
                ready.set()
                self.upsert(c, user, item, second[0], second[1])
        try:
            self.upsert(owner, user, item, first[0], first[1])
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(waiter)
                assert ready.wait(5)
                blocked = False
                try:
                    # A bounded barrier observes a real PostgreSQL lock wait, not a guessed sleep.
                    with self.connect() as observer:
                        observer.autocommit = True
                        end = time.monotonic() + 5
                        while time.monotonic() < end:
                            state = observer.execute("select wait_event_type from pg_stat_activity where application_name=%s", (tag,)).fetchone()
                            if state and state[0] == 'Lock':
                                blocked = True; break
                            if future.done():
                                future.result(); break
                            threading.Event().wait(0.01)
                    assert blocked, 'Actual concurrent conflict lock not observed'
                finally:
                    owner.commit()
                future.result(timeout=10)
        finally:
            owner.close()
        assert self.row(user, item) == expected

    def check(self, label, action):
        action()
        self.results.append(label)
        print(label + ' PASS', flush=True)

    def rest_parity(self, user, token, other, other_token):
        item = uuid.uuid4().hex
        path = '/rest/v1/user_recipes?on_conflict=user_id,kind,id'
        def write(stamp, deleted=False, uid=user, bearer=token):
            return self.request('POST', path, token=bearer, body=[{
                'user_id': uid, 'kind': 'shopping', 'id': item,
                'data': {'name': 'fixture'}, 'updated_at': stamp, 'deleted': deleted}])
        assert write(200, True)[0] in (200, 201)
        assert write(100)[0] in (200, 201)
        assert self.row(user, item) == (200, True)
        assert write(200, False)[0] in (200, 201)
        assert self.row(user, item) == (200, True)
        # Authenticated user B cannot modify or select user A's row.
        assert write(999, False, bearer=other_token)[0] in (401, 403)
        query = '/rest/v1/user_recipes?user_id=eq.' + user + '&id=eq.' + item
        code, rows = self.request('GET', query, token=other_token)
        assert code == 200 and rows == []
        with self.connect(other) as c:
            assert c.execute('select count(*) from public.user_recipes where user_id=%s', (user,)).fetchone()[0] == 0
            try:
                with c.transaction():
                    self.upsert(c, user, item, 999)
            except Exception:
                pass
            else:
                raise AssertionError('Cross-owner database write permitted')
        assert self.row(user, item) == (200, True)
        # Same item id remains independent for B.
        assert write(300, False, uid=other, bearer=other_token)[0] in (200, 201)
        assert self.row(other, item) == (300, False)

    def run(self):
        # Refuse an arbitrary local database too: only the isolated bootstrap creates this marker.
        with self.connect() as c:
            marker = c.execute('select purpose from public.ate501_disposable').fetchall()
            assert marker == [('shopping-conflict-proof-only',)]
            assert c.execute('select count(*) from auth.users').fetchone()[0] == 0
            self.server_version = c.execute('show server_version').fetchone()[0]
        # The workflow bootstraps only the existing user_recipes migration in an isolated stack.
        with self.connect() as c:
            c.execute((ROOT/'supabase/review-candidates/shopping_monotonic_sync.sql').read_text())
        user, token = self.create_user()
        other, other_token = self.create_user()
        self.check('newer-first-stale-second-real-lock', lambda: self.race(user, (200,False), (100,False), (200,False)))
        self.check('stale-first-newer-second-real-lock', lambda: self.race(user, (100,False), (200,False), (200,False)))
        self.check('newer-tombstone-rejects-stale-live', lambda: self.race(user, (200,True), (100,False), (200,True)))
        self.check('equal-tombstone-first-committer-wins', lambda: self.race(user, (200,True), (200,False), (200,True)))
        self.check('equal-live-first-committer-wins', lambda: self.race(user, (200,False), (200,True), (200,False)))
        self.check('postgrest-conflict-parity-and-two-user-rls', lambda: self.rest_parity(user, token, other, other_token))
        with self.connect() as c:
            c.execute('alter table public.user_recipes disable trigger shopping_preserve_newer_sync')
        try:
            # Mutation control must demonstrate stale overwrite using exactly the same race assertion.
            # A missing-lock/infrastructure error is NOT accepted as the intended negative control.
            self.race(user, (200,False), (100,False), (100,False))
            self.results.append('unguarded-stale-overwrite-observed')
            print('unguarded-stale-overwrite-observed PASS', flush=True)
        finally:
            with self.connect() as c:
                c.execute('alter table public.user_recipes enable trigger shopping_preserve_newer_sync')
        self.check('guard-restored-rejects-stale', lambda: self.race(user, (200,False), (100,False), (200,False)))

    def cleanup(self):
        for user in self.users:
            code, _ = self.request('DELETE', '/auth/v1/admin/users/' + user, service=True)
            assert code in (200, 204)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--status-file', required=True, type=Path)
    parser.add_argument('--receipt', required=True, type=Path)
    args = parser.parse_args()
    proof = None
    passed = False
    try:
        proof = LocalProof(json.loads(args.status_file.read_text()))
        proof.run()
        passed = True
    except Exception:
        print('local-shopping-proof FAIL (details suppressed to protect local credentials)', flush=True)
    finally:
        if proof:
            try:
                proof.cleanup()
            except Exception:
                passed = False
                print('local-fixture-cleanup FAIL', flush=True)
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps({'passed': passed, 'checks': proof.results if proof else [],
            'source_sha': os.environ.get('GITHUB_SHA'),
            'postgres_version': getattr(proof, 'server_version', None),
            'candidate_sha256': hashlib.sha256((ROOT/'supabase/review-candidates/shopping_monotonic_sync.sql').read_bytes()).hexdigest(),
            'scope': 'disposable-local-only; no hosted deployment'}, indent=2) + '\n')
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
