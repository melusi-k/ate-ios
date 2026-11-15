from test_failure_boundary_diagnostic import before_failure_receipts
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class CookRemovalOffMainTests(unittest.TestCase):
    def test_ordered_intent_owner_unchanged(self):
        source=(ROOT/'Ate/Services/CookPlanNotifications.swift').read_text()
        source=before_failure_receipts('Ate/Services/CookPlanNotifications.swift',source)
        owner=source[source.index('@MainActor\nfinal class CookPlanNotifications {'):]
        self.assertEqual(hashlib.sha256(owner.encode()).hexdigest(), 'ca7a8c6652c46909a5d44a0276e2141e6a02bac377c495845ce2675afca45431')
    def test_all_original_native_tests_preserved(self):
        source=(ROOT/'AteTests/CookPlanNotificationTests.swift').read_text()
        original=source.split('// Exercise the real off-Main boundary without contacting notification services.')[0]
        self.assertEqual(hashlib.sha256(original[:-1].encode()).hexdigest(), 'fce7986310514337704a2f650904a3b84fc4651cba1b7a334c0a5885397c753b')
    def test_system_removal_is_awaited_and_empty_is_no_op(self):
        source=(ROOT/'Ate/Services/CookPlanNotifications.swift').read_text()
        source=before_failure_receipts('Ate/Services/CookPlanNotifications.swift',source)
        self.assertEqual(source.count('await CookPlanNotificationRemoval.perform(ids: ids)'),2)
        helper=source.split('enum CookPlanNotificationRemoval {')[1].split('@MainActor')[0]
        self.assertIn('guard !ids.isEmpty else { return }',helper)
        self.assertLess(helper.index('operation(ids)'),helper.index('continuation.resume()'))
        self.assertIn('DispatchQueue.global(qos: .utility).async',helper)
        self.assertNotIn('asyncAfter',helper)
