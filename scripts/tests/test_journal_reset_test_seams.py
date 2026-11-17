"""Source contracts only. Native compile/XCTest/pixels remain UNRUN."""
import json,hashlib,unittest
from pathlib import Path
from journal_reset_test_seams_delta import restore,FIXTURE,DIGEST
ROOT=Path(__file__).resolve().parents[2]
class JournalResetTestSeams(unittest.TestCase):
    def test_exact_inverse_and_mutations(self):
        self.assertEqual(hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),DIGEST)
        for key,item in json.loads(FIXTURE.read_bytes()).items():
            source=(ROOT/key.removeprefix('source:')).read_text()
            self.assertEqual(hashlib.sha256(restore(key,source).encode()).hexdigest(),item['base'])
            for changed in [source+'// mutation\n',source.replace(item['fragments'][0]['new'],'',1),source+item['fragments'][0]['new']]:
                with self.assertRaises(AssertionError):restore(key,changed)
    def test_fixture_is_debug_and_explicit_and_keychain_unchanged(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text()
        flag=source.index('-qaJournalResetMemoryCredentials')
        self.assertGreater(source.rfind('#if DEBUG',0,flag),source.rfind('#endif',0,flag))
        self.assertIn('if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaJournalResetMemoryCredentials")',source)
        self.assertIn('credentialBytes = data',source)
        self.assertNotIn('Keychain',source[flag:source.index('CookJournalQARoute.prepare(st)',flag)].replace('OS Keychain entitlements',''))
    def test_original_assertion_and_cleanup_failure_remain_distinct(self):
        unit=(ROOT/'AteTests/AppStoreWriterBoundaryTests.swift').read_text()
        self.assertIn('XCTAssertEqual(store.session, afterWork ? nil : original)',unit)
        self.assertIn('precedingEffects: deleting ? 0 : 1',unit)
        self.assertIn('testSignOutCleanupEffectFailureDoesNotReachSessionPublicationOrRecipeWipe',unit)
        self.assertIn('XCTAssertEqual(credentialWrites, 0)',unit)
        ui=(ROOT/'AteUITests/JournalPersonalResetUITests.swift').read_text()
        self.assertIn('for _ in 0..<6 where !button.exists { app.swipeDown() }',ui)
        self.assertIn('wait(button); XCTAssertTrue(button.isHittable); button.tap()',ui)
