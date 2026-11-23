"""Terminal cover generation: a hung system stream must stop the shimmer; fixture settles."""
from pathlib import Path
import hashlib
import unittest
from cover_generation_terminal_delta import restore as restore_terminal

ROOT = Path(__file__).resolve().parents[2]
STORE = 'Ate/Services/CoverStore.swift'
FIXTURE = 'Ate/App/ExploreRetentionQAFixtures.swift'


class CoverGenerationTerminalTests(unittest.TestCase):
    def test_generation_attempt_is_deadline_bounded_and_reaches_terminal_state(self):
        source = (ROOT / STORE).read_text()
        self.assertIn('nonisolated static let generationDeadlineSeconds: UInt64 = 45', source)
        self.assertIn('@ObservationIgnored private var coverGenerationAttempts: [String: UInt64] = [:]', source)
        generate = source[source.index('    func generate(for r: RecipeCard) async -> String? {'):]
        generate = generate[:generate.index('\n    }')]
        self.assertIn('return await runCoverAttempt(for: r) {', generate)
        self.assertIn('for try await img in creator.images(for: [.text(text)], style: style, limit: 1) {', generate)
        self.assertIn('return img.cgImage', generate)
        self.assertNotIn('save(', generate, 'generate must commit only through the effect-boundary seam')
        runner = source[source.index('    func runCoverAttempt('):]
        runner = runner[:runner.index('\n    }')]
        self.assertIn('let attempt = beginCoverAttempt(for: r)', runner)
        self.assertIn('beginCoverLoading(r.id)', runner)
        self.assertIn('defer { endCoverLoading(r.id) }', runner)
        self.assertNotIn('wasLoading', runner, 'loading cleanup must be refcount ownership, not a first-insert flag')
        self.assertNotIn('loading.remove', runner, 'the runner must release through the ownership primitive')
        self.assertIn('let produced = await Self.withTerminalDeadline(seconds: seconds, produce)', runner)
        self.assertIn('return commitGeneratedCover(produced, attempt: attempt, for: r)', runner)
        self.assertNotIn('save(', runner, 'the runner must commit only through the seam')
        seam = source[source.index('    func commitGeneratedCover('):]
        seam = seam[:seam.index('\n    }')]
        boundary = 'guard let produced,\n              coverGenerationAttempts[r.id] == attempt,\n              (try? validateWriter()) != nil else { return nil }'
        self.assertIn(boundary, seam)
        self.assertIn('return save(UIImage(cgImage: produced), recipeID: r.id, source: .generated)', seam)
        self.assertLess(seam.index(boundary), seam.index('return save('))

    def test_deadline_helper_cannot_hang_on_an_uncooperative_stream(self):
        source = (ROOT / STORE).read_text()
        helper = source[source.index('    nonisolated static func withTerminalDeadline<T>'):]
        helper = helper[:helper.index('    /// Monotonic per-recipe attempt identity')]
        self.assertNotIn('withTaskGroup', helper)
        self.assertNotIn('await group', helper)
        self.assertNotIn('final class', helper, 'ResumeBox must not be a local type inside the generic function')
        self.assertIn('let box = ResumeBox<T>()', helper)
        self.assertEqual(helper.count('Task {'), 2)
        self.assertIn('let work = Task { box.resume(with: await operation()) }', helper)
        self.assertIn('box.resume(with: nil)', helper)
        self.assertIn('let result = await box.wait()\n        work.cancel()\n        timer.cancel()\n        return result', helper)
        box = source[source.index('final class ResumeBox<T>: @unchecked Sendable {'):]
        box = box[:box.index('/// Recipe cover images')]
        self.assertIn('continuation.resume(returning: value)', box)

    def test_availability_check_runs_under_the_same_deadline(self):
        source = (ROOT / STORE).read_text()
        check = source[source.index('    static func checkPlayground() async {'):]
        check = check[:check.index('\n    }')]
        self.assertIn('await withTerminalDeadline(seconds: generationDeadlineSeconds)', check)
        self.assertIn('"ImageCreator availability check timed out"', check)
        self.assertIn('playgroundAvailable = outcome?.0 ?? false', check)

    def test_loading_marker_is_refcounted_across_resolve_and_attempts(self):
        source = (ROOT / STORE).read_text()
        self.assertIn('@ObservationIgnored private var loadingHolders: [String: Int] = [:]', source)
        self.assertIn('loadingHolders[id, default: 0] += 1', source)
        resolve = source[source.index('    func resolve(_ r: RecipeCard, allowGenerate: Bool = true)'):]
        resolve = resolve[:resolve.index('    /// Image Playground is tried for every recipe')]
        self.assertIn('beginCoverLoading(r.id); defer { endCoverLoading(r.id) }', resolve)
        self.assertNotIn('defer { loading.remove(r.id) }', resolve,
                         'resolve must release through the ownership primitive, never unconditionally')
        self.assertEqual(source.count('loading.remove(id)'), 1,
                         'endCoverLoading must be the only place the marker is removed')

    def test_backfill_paths_and_attempted_marker_unchanged(self):
        source = (ROOT / STORE).read_text()
        ensure = source[source.index('    func ensure(_ r: RecipeCard, store: AppStore) {'):]
        ensure = ensure[:ensure.index('    /// Finds a cover for a recipe without a user photo')]
        self.assertNotIn('isUITesting', ensure)
        self.assertIn('await resolve(r)', ensure)
        self.assertIn('UserDefaults.standard.set(true, forKey: "ate.cover.gen.\\(r.id)")', source)
        self.assertIn('req.setValue("image/*", forHTTPHeaderField: "Accept")', source)

    def test_fixture_uses_the_real_settled_cover_state_not_a_bypass(self):
        source = (ROOT / FIXTURE).read_text()
        self.assertIn('miso.coverImage = CoverStore.removed', source)
        self.assertIn('store.recipes = [miso]', source)
        self.assertNotIn('coverImage: CoverStore.removed)]', source,
                         'RecipeCard init takes no coverImage - assign through the model property')
        self.assertNotIn('isUITesting) { return }', (ROOT / STORE).read_text())
        store = (ROOT / STORE).read_text()
        self.assertIn('nonisolated static let removed = "none"', store)
        self.assertIn('if r.coverImage == Self.removed || image(for: r) != nil || attempted.contains(r.id) { return }', store)

    def test_native_deadline_behavior_tests_exist(self):
        tests = (ROOT / 'AteTests/CoverTerminalDeadlineTests.swift').read_text()
        for name in ['testNeverSettlingOperationReachesTerminalNilAfterDeadline',
                     'testSettlingOperationReturnsItsValueBeforeDeadline',
                     'testFailingOperationSettlesImmediatelyWithoutWaitingForDeadline',
                     'testDeadlineThenLateCompletionCannotCommit',
                     'testSupersededAttemptCannotCommit',
                     'testEpochRejectionCannotCommit',
                     'testFailedAttemptClearsLoadingImmediately',
                     'testSupersededAttemptDoesNotClearLoadingOfCurrentAttempt',
                     'testResolveCompletionDoesNotClearOverlappingAttemptShimmer']:
            self.assertIn('runCoverAttempt' if 'DeadlineThen' in name or 'FailedAttempt' in name else '', tests + 'x')
            self.assertIn(name, tests)

    def test_explore_ui_test_file_is_byte_untouched(self):
        self.assertEqual(hashlib.sha256((ROOT / 'AteUITests/ExploreUITests.swift').read_bytes()).hexdigest(),
                         '5b25d18ee574c5436c77471830a6f21ca6b7976227be9d74239a3fbdf4e0680c')

    def test_exact_inverse_restores_historical_sources(self):
        restored = restore_terminal(STORE, (ROOT / STORE).read_bytes())
        self.assertEqual(hashlib.sha256(restored).hexdigest(),
                         '8c7d0dea1023a74c64b99db9c2df5bc954a4363693aa87c994196c0b4af2e75c')
        self.assertNotIn('withTerminalDeadline', restored.decode())
        restored_fixture = restore_terminal(FIXTURE, (ROOT / FIXTURE).read_bytes())
        self.assertEqual(hashlib.sha256(restored_fixture).hexdigest(), '1cf24d260d4b51b905d5367932383f101308ee84cab60621e1d66b86a0000701')
        self.assertNotIn('coverImage', restored_fixture.decode())
