from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class RecipeShoppingSyncCoreTests(unittest.TestCase):
    def test_no_production_install_or_legacy_upload_fallback(self):
        owner=(ROOT/'Ate/Store/RecipeShoppingSyncOwner.swift').read_text()
        for required in ['currentSession() == session', 'before == after', 'snapshot.capture.generation == after.generation', 'try await adapter.push(records, capture: capture)', 'try requireCycle(token)', 'func abandonCycle() { invalidateCycle() }']:
            self.assertIn(required,owner)
        for file in ['Ate/App/AteApp.swift','Ate/Store/AppStore.swift']:
            self.assertNotIn('RecipeShoppingSyncOwner(', (ROOT/file).read_text())
    def test_durable_journal_original_gate_then_replay_no_upload(self):
        source=(ROOT/'Ate/Store/RecipeShoppingSyncCommitJournal.swift').read_text()
        for required in ['try gate.withWriterEffect(writerLease)', 'try authorize(receipt)', 'try self.checkpoint(.beforeStoreSave)', 'try self.checkpoint(.afterStoreSave)', 'try install(encode(intent.authority), at: authorityURL)', 'defaults.set(intent.authority.metadata, forKey: "ate.sync.v1")', 'func recoverAndProject() throws -> Bool']:
            self.assertIn(required,source)
        self.assertNotIn('adapter.push',source)
        self.assertNotIn('URLSession',source)

    def test_fenced_staged_cycle_keeps_one_owner_until_commit_and_remains_uninstalled(self):
        source=(ROOT/'Ate/Store/FoodJournalGenerationSync.swift').read_text()
        cycle=source.split('func syncRecipeShopping(session:')[1]
        self.assertIn('guard !busy, pending == nil',cycle)
        self.assertIn('defer { busy = false; pending = nil }',cycle)
        self.assertEqual(cycle.count('guard try readLocal() == local'),2)
        self.assertLess(cycle.index('try await fenced.push(stage.upload'),cycle.index('try commit(stage, local,'))
        self.assertEqual(cycle.count('try require(session, capture: snapshot.capture)'),2)
        host=(ROOT/'Ate/Store/FoodJournalApplicationOwner.swift').read_text()
        self.assertNotIn('syncRecipeShopping(',host)
