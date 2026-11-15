"""Merged source wiring checks; native mock-transport execution remains required."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class Merge532SyncSemantics(unittest.TestCase):
    def test_owner_task_wraps_serialized_sync_and_bounded_shopping_reconciliation(self):
        s=(ROOT/'Ate/Store/AppStore.swift').read_text()
        wrapper=s.split('    func syncNow(reconcileShoppingPush: Bool = true) async {',1)[1].split('    private func syncNowOwned',1)[0]
        self.assertIn('guard !journalSyncInFlight else { syncRequestedWhileBusy = true; return }',wrapper)
        self.assertIn('defer { journalSyncInFlight = false }',wrapper)
        self.assertIn('try await tasks.run { [self] in await syncNowOwned(reconcileShoppingPush: reconcileShoppingPush) }',wrapper)
        owned=s.split('    private func syncNowOwned(reconcileShoppingPush: Bool) async {',1)[1].split('    private func signOutAfterFailedAccountSwitch()',1)[0]
        self.assertLess(owned.index('if syncInFlight { syncRequestedWhileBusy = true; return }'),owned.index('syncInFlight = true'))
        self.assertLess(owned.index('syncInFlight = true'),owned.index('try await sync.pull(session: s)'))
        self.assertIn('syncInFlight = false',owned)
        self.assertIn('scheduleSync(delay: 0.2, reconcileShoppingPush: false)',owned)
        self.assertIn('if reconcileShoppingPush && out.contains(where: { $0.kind == "shopping" }) { needsShoppingReconciliation = true }',owned)
        self.assertIn('session == capturedSession && validatePostAwaitPublish(capturedSession: capturedSession)',owned)
        self.assertIn('try SyncPayloadSafety.validate(remote, owner: s.userID)',owned)
        self.assertIn('if let transition = journalSessionTransition',owned)
    def test_server_wins_equal_recipe_and_shopping_stamps_with_both_native_tests_retained(self):
        s=(ROOT/'Ate/Services/Sync.swift').read_text()
        self.assertIn('guard Double(r.updated_at) >= localStamp else { continue }',s)
        native=(ROOT/'AteTests/ShoppingLiveSyncTests.swift').read_text()
        for text in ['testMergedEqualTimestampRecipesAndShoppingTakeServerPayload',
                     'XCTAssertEqual(result.data["r"], Data("server".utf8))',
                     'XCTAssertEqual(shopping.data["s"], Data("shopping-server".utf8))',
                     'testReentrantRequestDoesNotStartOverlappingPull',
                     'testOwnerBoundReentrantSyncKeepsOnePullAndOnePush',
                     'tested.journalConsumerTasks = FoodJournalConsumerTasks(lifecycle: lifecycle)',
                     'XCTAssertEqual(transport.pulls, 1', 'XCTAssertEqual(transport.pushes, 1)']:
            self.assertIn(text,native)
    def test_all_reorder_acceptance_journeys_are_independent_and_selected(self):
        native=(ROOT/'AteUITests/AteUITests.swift').read_text()
        workflow=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        for name in ['test29_ReorderMyOrder','test29a_MyOrderSelectionOnly','test29b_ReorderMyOrderActions','test29_DragMyOrder']:
            self.assertEqual(native.count('func '+name+'()'),1)
            self.assertIn('-only-testing:AteUITests/AteUITests/'+name+' \\',workflow)
        original=native.split('func test29_ReorderMyOrder()',1)[1].split('\n    func ',1)[0]
        self.assertIn('app.buttons["Move up"].tap()',original)
        self.assertIn('"moved up"',original)
        self.assertIn('"$total" -lt 16',workflow)
