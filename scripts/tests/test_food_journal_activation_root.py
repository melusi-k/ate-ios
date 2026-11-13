from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class FoodJournalActivationRootTests(unittest.TestCase):
    def test_production_branch_returns_before_legacy_ordinary_open(self):
        app = (ROOT / 'Ate/App/AteApp.swift').read_text()
        self.assertLess(app.index('if AppConfig.useFoodJournalProductionOwner'), app.index('StoreRecovery.open('))
        prefix = app.split('if AppConfig.useFoodJournalProductionOwner', 1)[1].split('// Corruption-safe open', 1)[0]
        self.assertIn('return // no ordinary constructors', prefix)
        self.assertIn('static let foodJournalEnabled = false', (ROOT / 'Ate/Services/BackendService.swift').read_text())
        self.assertIn('FoodJournalApplicationRoot()', app)

    def test_real_owner_resumes_before_rebuild_and_injects_real_graph(self):
        source = (ROOT / 'Ate/Store/FoodJournalApplicationOwner.swift').read_text()
        start = source.split('func start() async', 1)[1].split('static func decodeSession', 1)[0]
        self.assertLess(start.index('refreshStartupSessionIfNeeded'), start.index('resumeLocalActionIfPending'))
        self.assertLess(start.index('resumeLocalActionIfPending'), start.index('try await rebuild()'))
        self.assertLess(start.index('resumeIfPending()'), start.index('try await rebuild()'))
        for forbidden in ['AppStore(', 'TimerCenter(', 'StoreRecovery.open(', 'JournalStore.shared']:
            self.assertNotIn(forbidden, start)
        for contract in ['tasks = FoodJournalConsumerTasks(lifecycle: graph.lifecycle, sharedBoundary: boundary.sharedBoundary)',
                         'injectedSync: sync', 'draftStore: draft, timers: timers, coverStore: covers, insightsModel: insights',
                         'currentSession: { self.session }', 'snapshot: rpc.snapshot', 'journalRecoverySessionTransition',
                          'control.read() == bytes', 'record.phase == "localErase"', 'try control.read() == originalControl',
                         'try receipts.read() == originalReceipt', 'replacement.userID == original.userID', 'try Keychain.loadVerified',
                         'graph.lifecycle.register', 'drainOwner()', 'requiresCapturedOwner']:
            self.assertIn(contract, source)
        self.assertNotIn('resetForTesting', source)
        self.assertNotIn('SupabaseSync(', source)
        self.assertIn('directory = shared.resolvingSymlinksInPath()', source)
        self.assertIn('appOnlyContainerMode', source)

    def test_retirement_removes_root_and_checks_actual_disappearance_before_drain(self):
        owner = (ROOT / 'Ate/Store/FoodJournalApplicationOwner.swift').read_text()
        root = (ROOT / 'Ate/Views/FoodJournalApplicationRoot.swift').read_text()
        retirement = owner.split('private func retireEditors()', 1)[1].split('private func rawInventory', 1)[0]
        self.assertLess(retirement.index('state = .checking'), retirement.index('withCheckedContinuation'))
        self.assertIn('retirementWaiter?.resume()', owner)
        self.assertIn('.onDisappear { owner.unmounted(id) }', root)
        self.assertIn('.id(id)', root)

    def test_editor_and_health_work_are_captured_and_full_account_copy_is_honest(self):
        add = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('await store.runJournalTask { await generateOwned() }', add)
        self.assertIn('try await store.performJournalTask', add)
        self.assertIn('try store.validateJournalTask()', add)
        self.assertNotIn('CoverStore.shared', add)
        health = (ROOT / 'Ate/Views/InsightsView.swift').read_text()
        self.assertIn('let originalOwner = owner', health)
        self.assertIn('!Task.isCancelled, (try? validate()) != nil', health)
        self.assertNotIn('if let st = AppStore.current', health)
        settings = (ROOT / 'Ate/Views/SettingsView.swift').read_text()
        self.assertIn('Clear all your Ate account data?', settings)
        self.assertIn('Recipe links are not supported by this archive version', settings)
        self.assertIn('CookPlanStore.storageKey', (ROOT / 'Ate/Store/ClearAllDataKeys.swift').read_text())

    def test_extensions_bootstrap_before_shared_writes_and_share_image_captures_owner(self):
        shared = (ROOT / 'Shared/SharedWriterGate.swift').read_text()
        self.assertIn('Bundle.main.bundleURL.pathExtension == "appex"', shared)
        self.assertIn('return (try? extensionProvider()) ?? .requiresCapturedOwner', shared)
        self.assertIn('SharedWriterBoundary.installExtensionStartup()', (ROOT / 'AteWidgets/AteWidgets.swift').read_text())
        share = (ROOT / 'AteShare/ShareViewController.swift').read_text()
        self.assertIn('SharedWriterBoundary.installExtensionStartup()', share)
        self.assertLess(share.index('let boundary = SharedWriterBoundary.current'), share.index('await saveImage'))
        self.assertIn('private func saveImage(_ p: NSItemProvider, boundary: SharedWriterBoundary)', share)
        self.assertIn('SharedInbox.saveImage(boundary: boundary', share)
        self.assertIn('SharedInbox.push(item, boundary: boundary)', share)
        watch = (ROOT / 'AteWatch/WatchStore.swift').read_text()
        self.assertIn('rest/v1/rpc/account_data_snapshot', watch)
        self.assertIn('rest/v1/rpc/put_user_recipe', watch)
        self.assertIn('try content.prepareToggle(item, session: originalSession', watch)
        self.assertIn('try content.validate(capture, session: session)', watch)
        self.assertIn('"p_caller_generation": capture.generation', watch)
        self.assertNotIn('rest/v1/user_recipes', watch)

    def test_timer_os_submissions_are_awaited_and_closed_owner_is_drained(self):
        alerts = (ROOT / 'Ate/Services/TimerAlerts.swift').read_text()
        self.assertNotIn('.add(req)', alerts)
        self.assertIn('Task.sleep(nanoseconds: 300_000_000)', alerts)
        owner = (ROOT / 'Ate/Store/FoodJournalApplicationOwner.swift').read_text()
        self.assertIn('timers.notificationQueue.closeOwner()', owner)
        self.assertIn('await timers.notificationQueue.drainOwner()', owner)
        queue = (ROOT / 'Shared/OrderedTimerNotifications.swift').read_text()
        self.assertIn('try await self.add(request)', queue)
        self.assertIn('await previous?.value', queue)
        gate = (ROOT / 'Ate/Store/AccountWriterGate.swift').read_text()
        self.assertEqual(gate.count('try SharedNotificationSubmission.requireDrained(directory: directory)'), 3)
        intents = (ROOT / 'SharedWidgets/TimerIntents.swift').read_text()
        self.assertIn('try? await c.add(', intents)
        self.assertIn('SharedNotificationSubmission.begin(directory:', intents)
        self.assertIn('try? pair.submission.finish()', intents)
        self.assertIn('try? result.submission.finish()', intents)

    def test_watch_cache_and_retained_items_are_bound_to_actual_session_and_snapshot(self):
        watch = (ROOT / 'AteWatch/WatchStore.swift').read_text()
        content = (ROOT / 'Shared/Watch/WatchOwnedContent.swift').read_text()
        self.assertIn('content = WatchOwnedContent(session: saved, cacheURL: url)', watch)
        self.assertNotIn('private struct Cache', watch)
        self.assertIn('try content.transition(to: next, cacheURL: cacheURL)', watch)
        self.assertLess(watch.index('try content.transition(to: next'), watch.index('session = next'))
        self.assertIn('guard setSession(s) else { return }', watch)
        self.assertIn('try content.publish(result.0, session: expected, cacheURL: cacheURL)', watch)
        self.assertIn('cache.format == 2, cache.ownerID == owner', content)
        self.assertIn('item.snapshotID = nil', content)
        self.assertIn('retained.snapshotID == revision', content)
        self.assertIn('shopping[index] == retained', content)
        self.assertIn('generation == capture.generation, revision == capture.revision', content)
        self.assertIn('guard session == capture.session else {', watch)

    def test_real_owner_qualification_selector_is_debug_only_and_excludes_hermetic_fixture(self):
        config = (ROOT / 'Ate/Services/BackendService.swift').read_text()
        selector = config.split('static func foodJournalProductionOwnerSelected(arguments:', 1)[1].split('    static func string(', 1)[0]
        self.assertIn('guard !arguments.contains("-UITesting") else { return false }', selector)
        self.assertIn('#if DEBUG\n        if arguments.contains("-qaFoodJournalProductionOwner") { return true }\n        #endif', selector)
        release = selector.split('#if DEBUG', 1)[0] + selector.split('#endif', 1)[1]
        self.assertNotIn('-qaFoodJournalProductionOwner', release)
        self.assertNotIn('return true', release)
        self.assertIn('return foodJournalEnabled', release)
        self.assertIn('static let foodJournalEnabled = false', config)
        app = (ROOT / 'Ate/App/AteApp.swift').read_text()
        self.assertLess(app.index('if AppConfig.useFoodJournalProductionOwner'), app.index('if AppConfig.isUITesting'))
