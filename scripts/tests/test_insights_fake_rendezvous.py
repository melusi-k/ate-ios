"""Scoped fake donor only. Native execution UNRUN."""
from pathlib import Path
import hashlib,unittest
SOURCE=Path(__file__).resolve().parents[2]/'AteTests/InsightsRefreshOwnershipTests.swift'
DONOR_SHA256='c8e653d1ae895d88e06af4470881e2e3a531613984df18a6e578da5f8130e316'
BODY_SHA256='b32fa2543522b3af122eee7d0a97a94ba5150aa064a171bb162b9234a71f4af0'
class InsightsFakeRendezvousContracts(unittest.TestCase):
    def test_exact_reviewed_donor_and_untouched_test_body(self):
        raw=SOURCE.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),DONOR_SHA256)
        body=raw.split(b'@MainActor\nfinal class InsightsRefreshOwnershipTests',1)[1]
        self.assertEqual(hashlib.sha256(body).hexdigest(),BODY_SHA256)
    def test_atomic_waiter_registration_not_callback_install(self):
        source=SOURCE.read_text().split('@MainActor',1)[0]
        self.assertNotIn('onRead',source)
        self.assertEqual(source.count('private let lock = NSLock()'),2)
        self.assertEqual(source.count('waiters.append((count, continuation))'),2)
        self.assertEqual(source.count('if alreadyReady { continuation.resume() }'),2)
        self.assertEqual(source.count('for waiter in ready { waiter.resume() }'),2)
