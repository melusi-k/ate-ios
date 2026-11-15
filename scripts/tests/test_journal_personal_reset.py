"""Branch contracts only. Native compilation, XCTest and pixels remain UNRUN."""
import hashlib, json, unittest
from pathlib import Path
from unittest.mock import patch
from journal_personal_reset_delta import restore, is_added, FIXTURE, FIXTURE_SHA256
ROOT = Path(__file__).resolve().parents[2]
class JournalPersonalResetContracts(unittest.TestCase):
    def test_inverse_and_all_added_files_are_exact(self):
        payload = FIXTURE.read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), FIXTURE_SHA256)
        for key, value in json.loads(payload).items():
            if key == '_added_files':
                for file in value: self.assertTrue(is_added(file, (ROOT/file).read_bytes()))
            else:
                self.assertEqual(hashlib.sha256(restore(key, (ROOT/key.removeprefix('source:')).read_bytes())).hexdigest(), value['base_sha256'])
    def test_modified_missing_duplicate_and_fixture_mutants_fail(self):
        data = json.loads(FIXTURE.read_bytes())
        for key, value in data.items():
            if key == '_added_files': continue
            raw = (ROOT/key.removeprefix('source:')).read_text()
            for fragment in value['inverse']:
                new = fragment['new']
                for changed in [raw.replace(new, '', 1), raw + new, raw.replace(new, new+'// mutation\n', 1)]:
                    with self.assertRaises(AssertionError): restore(key, changed)
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p, *a, **kw: read(p)+b' ' if p == FIXTURE else read(p,*a,**kw)):
            with self.assertRaises(AssertionError): restore('source:Ate/Store/AppStore.swift', '')
        with self.assertRaises(AssertionError): is_added('AteTests/JournalPersonalResetTests.swift', b'mutation')
    def test_expiry_has_no_erase_and_guards_nil_session(self):
        source=(ROOT/'Ate/Store/AppStore.swift').read_text()
        expiry=source.split('    func expireSession() {',1)[1].split('    static let sessionExpiredMessage',1)[0]
        self.assertIn('guard session != nil else { return }', expiry)
        self.assertNotIn('eraseJournal', expiry)
        self.assertNotIn('wipeLocalData', expiry)
    def test_all_explicit_user_routes_erase_actual_owner(self):
        source=(ROOT/'Ate/Store/AppStore.swift').read_text()
        self.assertIn('try eraseJournalPersonalData()', source.split('func clearLibrary()',1)[1].split('private func removeCookPlans',1)[0])
        signout=source.split('func signOut(removeLocalData:',1)[1].split('func deleteAccount()',1)[0]
        self.assertLess(signout.index('try eraseJournalPersonalData()'),signout.index('guard setSession(nil)'))
        self.assertLess(signout.index('try eraseJournalPersonalData()'),signout.index('if removeLocalData {'))
        session=source.split('private func setSession(',1)[1].split('// MARK: onboarding',1)[0]
        self.assertLess(session.index('nextOwner != previousOwner'),session.index('try eraseJournalPersonalData()'))
        self.assertLess(session.index('try eraseJournalPersonalData()'),session.index('guard saveSessionCredentials(encoded)'))
        self.assertIn('?? journalOwnerFingerprint ?? meta.userID.map',session)
        self.assertIn('if let nextOwner { journalOwnerFingerprint = nextOwner }',session)
    def test_store_media_backups_and_drafts_are_in_inventory(self):
        source=(ROOT/'Ate/Store/AppStore+JournalPersonalReset.swift').read_text()
        for token in ['let journal = journalStore', 'inventory.journal === journal', 'inventory.defaults === defaults',
                      'inventory.components(validateWriterGate: validate)', 'commits.clearAllComponent',
                      'guard report.complete else', 'trackerPath = []', 'journalRevision += 1',
                      'manualJournalHost = nil; manualJournalDraft = ""', 'journalReflection = JournalReflectionDraft()',
                      'journalPersonalResetEpoch += 1', 'InsightsModel.shared.resetForJournalErase()',
                      'insights.lifecycle.v1.account.', 'mediaDirectory: JournalStore.mediaDir',
                      'migrationBackupDirectory:', 'repairBackupDirectory:', 'preservationDirectory:',
                      'SHA256.hash(data: Data(owner.utf8))', 'ate.journal.owner.v1']:
            self.assertIn(token,source)
        self.assertNotIn('removePersistentDomain',source)
        self.assertLess(source.index('journalPersonalResetEpoch += 1'),source.index('ClearAllLocalData.execute'))
        self.assertLess(source.index('journalRevision += 1'),source.index('guard report.complete else'))
    def test_in_flight_publication_cannot_ignore_reset_epoch(self):
        sync=(ROOT/'Ate/Store/AppStore+UserDataSync.swift').read_text()
        self.assertGreaterEqual(sync.count('journalPersonalResetEpoch == capturedResetEpoch'),4)
        revalidate=sync.index('                try revalidate()')
        commit=sync.index('let projected = try journal.commit(',revalidate)
        self.assertIn('journalPersonalResetEpoch == capturedResetEpoch',sync[revalidate:commit])
        source=(ROOT/'Ate/Store/AppStore.swift').read_text()
        self.assertIn('session == capturedSession && journalPersonalResetEpoch == capturedJournalResetEpoch',source)
    def test_native_action_cases_and_original_qa_bodies_retained(self):
        native=(ROOT/'AteTests/JournalPersonalResetTests.swift').read_text()
        for name in ['testSettingsClearAllErasesLegacyActualOwnerAndPersonalFiles',
            'testSettingsClearAllErasesBoundActualOwnerNotAnotherContainer',
            'testExplicitSignOutKeepRecipesStillErasesJournal',
            'testSwitchToDifferentAccountErasesBeforePublishingNewIdentity',
            'testDifferentAccountAfterExpiryWithoutCompletedSyncStillErasesJournal',
            'testSameAccountReauthenticationPreservesJournal', 'testExpiryPreservesJournalMealsFilesAndDrafts',
            'testRefusedWriterDoesNotEraseJournalOrPublishNewIdentity', 'testPartialEraseCannotClaimSuccessOrSwitchAccount']:
            self.assertIn('func '+name+'()',native)
        ui=(ROOT/'AteUITests/JournalPersonalResetUITests.swift').read_text()
        self.assertIn('testSettingsClearAllRemovesVisibleJournal',ui)
        self.assertIn('testExplicitSignOutKeepRecipesRemovesVisibleJournal',ui)
        self.assertIn('testExpiredTokenPreservesVisibleJournal',ui)
        self.assertNotIn('-qaJournalTimeline',ui)
        # This slice adds cases; no existing QA flow or timing budget changes.
        self.assertEqual(hashlib.sha256((ROOT/'AteUITests/KeyFlowsQATests.swift').read_bytes()).hexdigest(), '9085fc97e340f248bd5b101a479b02d451ddfdac42a7e8c216709ef88d2c930c')

    def test_ci_requires_each_new_ui_case_without_changing_existing_budgets(self):
        workflow=(ROOT/'.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/JournalPersonalResetUITests',workflow)
        for name in ['testSettingsClearAllRemovesVisibleJournal',
                     'testExplicitSignOutKeepRecipesRemovesVisibleJournal',
                     'testExpiredTokenPreservesVisibleJournal']:
            self.assertIn("JournalPersonalResetUITests "+name+"]' passed",workflow)
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',workflow)
