from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class FoodJournalOwnerContextTests(unittest.TestCase):
    def test_shared_context_is_task_captured_and_unowned_context_refuses(self):
        shared = (ROOT / 'Shared/SharedWriterGate.swift').read_text()
        self.assertIn('@TaskLocal private static var capturedOwner', shared)
        self.assertIn('if let capturedOwner { return capturedOwner }', shared)
        self.assertIn('static let requiresCapturedOwner', shared)
        self.assertIn('throw Failure.ownerContextRequired', shared)
        tasks = (ROOT / 'Ate/Store/FoodJournalConsumerTasks.swift').read_text()
        self.assertIn('[lifecycle, sharedBoundary]', tasks)
        self.assertIn('withCapturedOwner(sharedBoundary', tasks)
        boundary = (ROOT / 'Ate/Store/FoodJournalWriterBoundary.swift').read_text()
        self.assertIn('withCapturedOwner(sharedBoundary, work)', boundary)
        self.assertIn('captureSharedWrites: true', (ROOT / 'Ate/Store/FoodJournalLocalOwner.swift').read_text())

    def test_reset_inventory_has_unopened_route_and_preserves_control_namespace(self):
        source = (ROOT / 'Ate/Store/FoodJournalResetInventory.swift').read_text()
        for contract in ['case unopened', 'case retained', 'ClearAllDataKeys.standard.union(["ate.sync.v1"])',
                         'ClearAllDataKeys.shared', 'nutrition-goals-corrupt-', 'Ate-recovered-',
                         'txn-', '.resolved-', 'validateAncestors']:
            self.assertIn(contract, source)
        for forbidden in ['StoreRecovery.open(', 'JournalStore.shared', 'TimerCenter(', 'removePersistentDomain']:
            self.assertNotIn(forbidden, source)
