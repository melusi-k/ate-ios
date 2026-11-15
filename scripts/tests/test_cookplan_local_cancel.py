from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]
ADDITION = '    /// Local plan removal must not wait on notification XPC. Register cleanup in\n    /// the same ordered queue before the caller dismisses, preserving later adds.\n    /// Returning proves local removal only; failures still report unverified OS cleanup.\n    @discardableResult\n    func cancelLocally(recipeID: String, store: CookPlanStore,\n                       onRemovalFailure: @escaping @MainActor () -> Void) throws -> Task<Void, Never> {\n        try store.cancel(recipeID: recipeID)\n        let removal = enqueue { _ in try await self.removeAndVerify(recipeID: recipeID) }\n        return Task { @MainActor in\n            do { try await removal.value }\n            catch { onRemovalFailure() }\n        }\n    }\n\n'
OLD_CANCEL = '    private func cancel() {\n        busy = true\n        Task { @MainActor in\n            do {\n                try store.cookPlanStore.cancel(recipeID: recipeID)\n                try await store.cookPlanNotifications.cancel(recipeID: recipeID)\n                busy = false\n                store.show("Cooking plan cancelled")\n                dismiss()\n            } catch {\n                busy = false\n                problem = "Cancellation could not be verified. Try again to remove the reminder."\n            }\n        }\n    }'
NEW_CANCEL = '    private func cancel() {\n        guard !busy else { return }\n        do {\n            try store.cookPlanNotifications.cancelLocally(recipeID: recipeID, store: store.cookPlanStore) {\n                store.show("Cooking plan removed, but reminder removal could not be verified. Check iPhone notifications before the planned time.", error: true)\n            }\n            existing = nil\n            // This confirms the verified local change, not completion of OS cleanup.\n            store.show("Cooking plan removed")\n            dismiss()\n        } catch {\n            problem = "Cooking plan removal could not be verified. Reopen the plan and try again."\n        }\n    }'
def restore_local_cancel(test, source):
    test.assertEqual(source.count(ADDITION), 1)
    return source.replace(ADDITION, '', 1)

class CookPlanLocalCancelContracts(unittest.TestCase):
    def test_exact_additive_adapter_inverse_keeps_original_verification_and_queue(self):
        source = (ROOT / "Ate/Services/CookPlanNotifications.swift").read_text()
        self.assertEqual(hashlib.sha256(restore_local_cancel(self, source).encode()).hexdigest(), '4948a4701ea465790e97d29a357d76e08d9031c25ca865aa051809aa1e1c2c55')
        self.assertLess(ADDITION.index("try store.cancel"), ADDITION.index("let removal = enqueue"))
        self.assertLess(ADDITION.index("let removal = enqueue"), ADDITION.index("return Task"))
        self.assertIn("try await self.removeAndVerify(recipeID: recipeID)", ADDITION)
        for mutant in [source.replace(ADDITION, ''), source + ADDITION]:
            with self.assertRaises(AssertionError): restore_local_cancel(self, mutant)

    def test_sheet_exact_reversal_and_honest_local_success(self):
        source = (ROOT / "Ate/Views/CookPlanSheet.swift").read_text()
        self.assertEqual(source.count(NEW_CANCEL), 1)
        self.assertEqual(hashlib.sha256(source.replace(NEW_CANCEL, OLD_CANCEL).encode()).hexdigest(), '75fb68558b403342dcbd9d790c48e16410c2b1122f52fa93c020b8de6c182d9e')
        for token in ['existing = nil', 'store.show("Cooking plan removed")', 'error: true', 'dismiss()']:
            self.assertIn(token, NEW_CANCEL)
        self.assertNotIn('await', NEW_CANCEL)
        self.assertNotIn('Cooking plan cancelled', NEW_CANCEL)
        self.assertLess(NEW_CANCEL.index('cancelLocally'), NEW_CANCEL.index('existing = nil'))

    def test_existing_ui_and_native_fixtures_byte_identical(self):
        files = {'AteUITests/CookPlanUITests.swift': '73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec', 'AteTests/CookPlanNotificationTests.swift': 'e8e42897e24abdbaf061c1b117df751de5443522663d51b8c0ea2027acc7596f', 'AteTests/CookPlanTests.swift': '853088fe48a5c916ab75eaf0d3158004d3e3909234d008501d7072b0104458a4'}
        for file, expected in files.items():
            self.assertEqual(hashlib.sha256((ROOT / file).read_bytes()).hexdigest(), expected, file)
