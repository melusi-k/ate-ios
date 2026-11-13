"""Keep the dormant binding seam from becoming an alternate destructive open path."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FoodJournalRuntimeFactoryGuardTests(unittest.TestCase):
    def test_factory_stays_dormant_and_no_fallback_maintenance_or_shared_domains(self):
        source = (ROOT / 'Ate/Store/FoodJournalRuntimeFactory.swift').read_text()
        for forbidden in ['StoreRecovery', '.shared', 'UserDefaults.standard', '= .standard', '.legacy', 'save()', 'removeItem',
                          'migrateIfNeeded', 'JournalStore()', 'ModelContainer(for:', 'seedMomentEntry',
                          'removeImagePromptEntriesOnce']:
            self.assertNotIn(forbidden, source)
        calls = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalRuntimeFactory.swift', 'FoodJournalLocalOwner.swift'}
                 and 'FoodJournalRuntimeFactory' in p.read_text()]
        self.assertEqual(calls, [])

    def test_factory_checks_storage_and_schema_before_building_runtime(self):
        source = (ROOT / 'Ate/Store/FoodJournalRuntimeFactory.swift').read_text()
        checks = ['openState == .ok', '!$0.isStoredInMemoryOnly', '$0.allowsSave',
                  'required.isSubset', '!container.mainContext.hasChanges',
                  'bindings.goals.defaults === bindings.defaults', 'paths.allSatisfy',
                  'FoodJournalStore(container: container).readMeals()', 'journal.readReflections()']
        for check in checks:
            self.assertIn(check, source)
            self.assertLess(source.index(check), source.index('return FoodJournalRuntime('))

    def test_runtime_cooking_history_uses_the_same_admission_boundary(self):
        source = (ROOT / 'Ate/Store/FoodJournalRuntime.swift').read_text()
        self.assertIn('CookingHistory(defaults: defaults, writerBoundary: writerBoundary)', source)
        history = (ROOT / 'Ate/Logic/CookingHistory.swift').read_text()
        self.assertEqual(history.count('writerBoundary.withEffect'), 3)
        self.assertIn('try recordHeld(recipeID: recipeID, date: date, dayKey: dayKey)', history)

    def test_local_owner_retains_original_lease_and_explicit_inventory(self):
        source = (ROOT / 'Ate/Store/FoodJournalLocalOwner.swift').read_text()
        for forbidden in ['.shared', '.legacy', 'captureWriter(', 'ModelContainer(for:', 'StoreRecovery', 'JournalStore.mediaDir']:
            self.assertNotIn(forbidden, source)
        self.assertIn('gate.withWriterEffect(admittedLease)', source)
        self.assertIn('writerLease: admittedLease, archive: archive', source)
        self.assertIn('preservationDirectory: locations.preservationDirectory', source)
        self.assertIn('func validate() throws {', source)
        self.assertIn('try gate.withWriterEffect(lease) { try validateConsumers() }', source)
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalLocalOwner.swift', 'FoodJournalDiskResources.swift', 'FoodJournalProductionAdmission.swift', 'FoodJournalArchiveExport.swift', 'FoodJournalArchiveImport.swift', 'FoodJournalProductionGraph.swift'}
                   and 'FoodJournalLocalOwner' in p.read_text()]
        self.assertEqual(callers, [])

    def test_journal_media_writers_use_bound_directory(self):
        source = (ROOT / 'Ate/Services/JournalSuggestionService.swift').read_text()
        self.assertIn('at: mediaDirectory, withIntermediateDirectories: true', source)
        self.assertIn('removeItem(at: boundMediaURL(name))', source)
        self.assertIn('let url = boundMediaURL(name)', source)
        self.assertNotIn('Self.mediaURL(name)', source)

    def test_unified_wipe_requires_retained_inventory_before_any_effect(self):
        source = (ROOT / 'Ate/Store/AppStore+JournalAccountActions.swift').read_text()
        wipe = source.split('func wipeLocalDataUnified()', 1)[1].split('func exportUserData()', 1)[0]
        self.assertIn('inventory.journal === runtime.journal', wipe)
        self.assertIn('inventory.defaults === runtime.defaults', wipe)
        self.assertIn('inventory.mediaDirectory == runtime.journal.mediaDirectory', wipe)
        self.assertLess(wipe.index('guard let inventory'), wipe.index('try effect {'))
        self.assertIn('inventory.eraseAll(validateWriterGate: validate)', wipe)
        self.assertNotIn('JournalLocalReset(runtime:', wipe)

    def test_media_consumers_follow_actual_owner_not_legacy_global(self):
        view = (ROOT / 'Ate/Views/JournalViews.swift').read_text()
        intent = (ROOT / 'Ate/Intents/AteAppIntents.swift').read_text()
        archive = (ROOT / 'Ate/Logic/JournalArchive.swift').read_text()
        for source in [view, intent, archive]:
            self.assertNotIn('JournalStore.mediaURL', source)
            self.assertNotIn('JournalStore.mediaDir', source)
        self.assertIn('store.journalStore.boundMediaURL($0).path', view)
        self.assertIn('init(_ e: JournalEntry, journal: JournalStore)', intent)
        self.assertEqual(intent.count('AteJournalEntryEntity($0, journal: journal)'), 3)
        self.assertIn('AteJournalEntryEntity(saved, journal: journal)', intent)
        self.assertIn('mediaDirectory ?? journal.mediaDirectory', archive)

    def test_injected_app_reflection_session_uses_runtime_admission(self):
        source = (ROOT / 'Ate/Store/AppStore.swift').read_text()
        method = source.split('func requestCookedReflection(', 1)[1].split('func presentPendingCookedReflection()', 1)[0]
        self.assertIn('if let runtime = foodJournalRuntime', method)
        self.assertIn('try runtime.reflectionSession(for: event.id)', method)
        self.assertIn('} else {', method)
        self.assertLess(method.index('runtime.reflectionSession'), method.index('CookedJournalReflectionStore(journal: cookJournalStore)'))
    def test_disk_resources_are_strict_recovery_before_ordinary_binding(self):
        source = (ROOT / 'Ate/Store/FoodJournalDiskResources.swift').read_text()
        for forbidden in ['StoreRecovery', 'UserDefaults.standard', '= .standard', '.shared', 'captureWriter(', 'JournalStore()', 'FoodJournalRuntime(']:
            self.assertNotIn(forbidden, source)
        self.assertLess(source.index('try authorizeRecovery()'), source.index('let recipes = try ModelContainer('))
        self.assertLess(source.index('UnifiedArchiveStartupRecovery.recoverAtStartup'), source.index('self.recipes = recipes'))
        self.assertIn('gate.withArchiveRecoveryLease(admittedLease)', source)
        gate = (ROOT / 'Ate/Store/AccountWriterGate.swift').read_text()
        section = gate.split('func withArchiveRecoveryLease', 1)[1].split('func invalidateWriters', 1)[0]
        self.assertIn('withWriterEffect(lease)', section)
        self.assertIn('POSIXArchiveWriterLease(nestedDirectory: directory)', section)
        self.assertNotIn('captureWriter(', section)
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalDiskResources.swift', 'FoodJournalProductionAdmission.swift', 'FoodJournalArchiveExport.swift', 'FoodJournalArchiveImport.swift', 'FoodJournalProductionGraph.swift'}
                   and 'FoodJournalDiskResources' in p.read_text()]
        self.assertEqual(callers, [])

    def test_production_admission_preserves_full_session_and_no_rpc_write(self):
        source = (ROOT / 'Ate/Store/FoodJournalProductionAdmission.swift').read_text()
        self.assertIn('currentSession() == session', source)
        self.assertIn('candidate == session', source)
        self.assertIn('try verifyOriginal()', source)
        self.assertIn('gate.usesControlDirectory(control.directory)', source)
        self.assertLess(source.index('remote = try await snapshot(session)'), source.index('try resources.recover('))
        self.assertLess(source.index('try resources.recover('), source.index('reconciliation.reconcile()'))
        for forbidden in ['.clear(', 'captureWriter(', 'StoreRecovery', '.shared', 'remote = AccountSnapshot']:
            self.assertNotIn(forbidden, source)
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalProductionAdmission.swift', 'FoodJournalProductionGraph.swift'}
                   and 'FoodJournalProductionAdmission' in p.read_text()]
        self.assertEqual(callers, [])

    def test_export_revalidates_owner_and_archive_generation_after_await(self):
        source = (ROOT / 'Ate/Store/FoodJournalArchiveExport.swift').read_text()
        self.assertIn('archive.generation == generation', source)
        self.assertIn('try validateOwner()', source)
        self.assertIn('recipeLinksNotArchived', source)
        self.assertIn('mediaDirectory: owner.locations.mediaDirectory', source)
        self.assertNotIn('JournalStore.mediaDir', source)
        self.assertNotIn('controlDirectory:', source)
        self.assertNotIn('commitGeneration(', source)
        self.assertLess(source.index('try await afterSnapshot()'), source.index('let result = try await capture.finish'))
        self.assertIn('gate.withArchiveRecoveryLease(admittedLease)', source)

    def test_consumer_lifecycle_closes_before_original_epoch_revocation_and_drains(self):
        source = (ROOT / 'Ate/Store/FoodJournalConsumerLifecycle.swift').read_text()
        self.assertIn('currentSession() == session', source)
        self.assertLess(source.index('state = .quiescing'), source.index('gate.invalidateWriters(expectedLease: admittedLease)'))
        self.assertLess(source.index('consumer.cancel()'), source.index('try await consumer.drain()'))
        self.assertLess(source.index('if let failure { throw failure }'), source.index('state = .quiesced'))
        self.assertNotIn('captureWriter(', source)
        gate = (ROOT / 'Ate/Store/AccountWriterGate.swift').read_text().split('func invalidateWriters(expectedLease:', 1)[1].split('/// Explicit auth lifecycle', 1)[0]
        self.assertLess(gate.index('readEpoch() == expectedLease'), gate.index('saveEpoch(replacement)'))
        owner = (ROOT / 'Ate/Store/FoodJournalLocalOwner.swift').read_text()
        self.assertLess(owner.index('try validateConsumers()', owner.index('let boundary =')), owner.index('try perform(effect)'))
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalConsumerLifecycle.swift', 'FoodJournalArchiveImport.swift', 'FoodJournalLocalOwner.swift', 'FoodJournalProductionAdmission.swift'} and 'FoodJournalConsumerLifecycle' in p.read_text()]
        self.assertEqual(callers, [])

    def test_quiesced_import_uses_its_revoked_epoch_handoff_and_exact_generation_order(self):
        source = (ROOT / 'Ate/Store/FoodJournalArchiveImport.swift').read_text()
        self.assertLess(source.index('UnifiedArchiveImportBinding.validate(archive)'), source.index('try await lifecycle.quiesce()'))
        self.assertLess(source.index('try await lifecycle.quiesce()'), source.index('withQuiescedArchiveOperation'))
        self.assertLess(source.index('binding.importArchive'), source.index('lease.commitGeneration'))
        self.assertLess(source.index('lease.commitGeneration'), source.index('recovery.retire'))
        for forbidden in ['captureWriter(', 'ArchiveStandaloneImportSession(', 'UserDefaults.standard', 'JournalStore.shared']:
            self.assertNotIn(forbidden, source)
        lifecycle = (ROOT / 'Ate/Store/FoodJournalConsumerLifecycle.swift').read_text()
        self.assertIn('quiescedOperationLease = try gate.invalidateWriters(expectedLease: admittedLease)', lifecycle)
        self.assertIn('operationConsumed = true', lifecycle)
        self.assertIn('try authorize()', lifecycle)
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name != 'FoodJournalArchiveImport.swift' and p.name != 'FoodJournalProductionAdmission.swift' and 'FoodJournalArchiveImport' in p.read_text()]
        self.assertEqual(callers, [])

    def test_retained_graph_comes_from_original_admission_proof_without_activation(self):
        source = (ROOT / 'Ate/Store/FoodJournalProductionAdmission.swift').read_text().split('func buildGraph(', 1)[1].split('func bindOwner(', 1)[0]
        self.assertIn('session: captured.session, currentSession: currentSession', source)
        self.assertIn('validateConsumers: lifecycle.validate', source)
        self.assertIn('ownerIdentity: captured.receipt.ownerID', source)
        self.assertIn('self.currentSession() == captured.session', source)
        self.assertIn('try self.receipts.read() == captured.receipt', source)
        self.assertIn('try self.control.read() == nil', source)
        self.assertNotIn('captureWriter(', source)
        self.assertNotIn('AppStore(', source)
        callers = [p for p in (ROOT / 'Ate').rglob('*.swift') if p.name not in {'FoodJournalProductionAdmission.swift', 'FoodJournalProductionGraph.swift'} and 'FoodJournalProductionGraph' in p.read_text()]
        self.assertEqual(callers, [])
