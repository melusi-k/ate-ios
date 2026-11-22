"""Pin test-only continuation registration, preserving strict late-result contracts."""
from pathlib import Path
import hashlib
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
FIXTURE_SHA = 'aeb6d21463eca91643d46fadf6073ad660e029b017d0b475c00ab710a09aca5c'

def restore(source):
    payload = (ROOT / 'scripts/tests/draft_registration_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    assert hashlib.sha256(source.encode()).hexdigest() == c['current_sha256']
    assert source == c['new']
    return c['old']

class DraftRegistrationTests(unittest.TestCase):
    def test_exact_inverse_and_registration_precedes_signal(self):
        c = json.loads((ROOT / 'scripts/tests/draft_registration_inverse.json').read_text())
        source = (ROOT / c['path']).read_text()
        self.assertEqual(hashlib.sha256(restore(source).encode()).hexdigest(), c['parent_sha256'])
        # Independently derive the complete legal source change from the original.
        expected = c['old'].replace(
            '        func parse() async -> RecipeCard { await withCheckedContinuation { continuation = $0 } }',
            '        func parse(onRegistered: (() -> Void)? = nil) async -> RecipeCard {\n            await withCheckedContinuation {\n                continuation = $0\n                onRegistered?()\n            }\n        }', 1)
        start = expected.index('    func testDisappearKeepsRetryInputButLateResultCannotReplaceIt()')
        prefix, target = expected[:start], expected[start:]
        target = target.replace('            started.fulfill()\n            let card = await backend.parse()',
            '            // Admit cancellation/completion only after the backend owns its continuation.\n            let card = await backend.parse(onRegistered: { started.fulfill() })', 1)
        self.assertEqual(source, prefix + target)
        self.assertEqual(source.count('timeout: 2'), c['old'].count('timeout: 2'))
        self.assertEqual(source.count('XCTAssert'), c['old'].count('XCTAssert'))
        for mutant in [source + '// unrelated', source.replace('onRegistered?()', ''), source.replace('timeout: 2', 'timeout: 3', 1), source.replace('                continuation = $0\n                onRegistered?()', '                onRegistered?()\n                continuation = $0')]:
            with self.assertRaises(AssertionError):
                restore(mutant)
