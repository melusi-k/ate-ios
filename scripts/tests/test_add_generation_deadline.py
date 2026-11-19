"""Source deadline wiring/inverse checks, not native or live-model qualification."""
from pathlib import Path
import hashlib,json,re,unittest
from add_generation_deadline_delta import restore
ROOT=Path(__file__).resolve().parents[2]

class AddGenerationDeadlineSourceTests(unittest.TestCase):
    def test_exact_inverse_and_missing_duplicate_unrelated_mutants(self):
        fixture=json.loads((ROOT/'scripts/tests/add_generation_deadline_inverse.json').read_text())
        for path, contract in fixture.items():
            source=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,source).encode()).hexdigest(),contract['parent_sha'])
            for f in contract['fragments']:
                for mutant in [source.replace(f['new'],'',1),source+f['new'],source+'// unrelated delta\n']:
                    with self.assertRaises(AssertionError):restore(path,mutant)

    def test_terminal_deadline_revokes_before_callback_without_waiting_for_backend(self):
        owner=(ROOT/'Ate/Logic/DraftGenerationAttempt.swift').read_text()
        timer=owner.split('        if let timeoutNanoseconds {',1)[1].split('    func startChild',1)[0]
        self.assertIn('self.token == value, self.isRunning',timer)
        self.assertLess(timer.index('self.invalidate()'),timer.index('timedOut()'))
        self.assertNotIn('await work',timer)
        self.assertNotIn('withTaskGroup',owner)
        revoke=owner.split('    func invalidate()',1)[1].split('    func start(',1)[0]
        self.assertLess(revoke.index('token = nil'),revoke.index('task?.cancel()'))
        self.assertIn('deadline?.cancel(); deadline = nil',revoke)
        self.assertIn('for child in children.values { child.cancel() }',revoke)
        self.assertIn('self.deadline?.cancel(); self.deadline = nil',owner)

    def test_add_uses_sixty_seconds_existing_error_retry_and_keeps_pending_input(self):
        view=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('static let generationTimeoutNanoseconds: UInt64 = 60_000_000_000',view)
        self.assertIn('generationAttempt.start(timeoutNanoseconds: Self.generationTimeoutNanoseconds, timedOut:',view)
        callback=view.split('timedOut: {',1)[1].split('}) { token',1)[0]
        self.assertIn('invalidateGeneration()',callback)
        self.assertIn('error = Self.generationTimeoutMessage',callback)
        self.assertNotIn('DraftStore',callback)
        self.assertIn('ErrorRetryCard(message: error, retryID: "generateRetry") { startGeneration() }',view)
        self.assertIn('guard generationAttempt.isCurrent(token) else { return }',view)
        self.assertIn('} else if let q = dishQuestion, error == nil {',view)
        self.assertIn('DraftStore.shared.begin(mode: mode.rawValue',view)
        discovery=(ROOT/'Ate/Logic/RecipeDiscovery.swift').read_text()
        self.assertIn('timeoutNanoseconds: UInt64 = 60_000_000_000',discovery)

    def test_all_native_uncooperative_regressions_required_without_old_test_edits(self):
        required=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        source=(ROOT/'AteTests/AddGenerationDeadlineTests.swift').read_text()
        for name in re.findall(r'    func (test\w+)\(',source):self.assertIn('AddGenerationDeadlineTests/'+name,required)
        self.assertIn('await work.wait()',source)
        self.assertIn('drafts.pending?.text',source)
        self.assertIn('XCTAssertTrue(attempt.isRunning)',source)
        self.assertIn('XCTAssertEqual(effects, ["new result"])',source)

    def test_stage_breadcrumbs_are_local_only_and_one_snapshot_per_generation(self):
        history=(ROOT/'Ate/Services/DiagnosticHistory.swift').read_text()
        local=history.split('    func recordLocal(',1)[1].split('    func clear()',1)[0]
        self.assertNotIn('TelemetryClient',local)
        self.assertIn('persistLocked()',local)
        self.assertIn('Self.maximumEntries',local)
        backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for stage in ['generationAttemptStarted','generationFetchStarted','generationFetchReturned','generationPromptBuilt','generationModelStarted','generationFirstSnapshot','generationModelReturned','generationRepairStarted','generationRepairReturned','generationAttemptReturned','generationAttemptFailed']:
            self.assertIn('recordLocal(.'+stage+')',backend)
        self.assertIn('if !recordedFirstSnapshot {',backend)
        self.assertEqual(backend.count('recordLocal(.generationFirstSnapshot)'),1)
        self.assertNotIn('DiagnosticHistory.shared.record(',backend)
        self.assertIn('recordLocal(.generationTimedOut)',(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text())

    def test_all_stage_native_cases_are_required_and_no_event_payload_added(self):
        source=(ROOT/'AteTests/GenerationStageHistoryTests.swift').read_text()
        required=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        for name in re.findall(r'    func (test\w+)\(',source):self.assertIn('GenerationStageHistoryTests/'+name,required)
        self.assertIn('Set(["id", "kind", "timestamp"])',source)
        history=(ROOT/'Ate/Services/DiagnosticHistory.swift').read_text()
        fields=history.split('    let id: UUID',1)[1].split('    init(',1)[0]
        self.assertEqual(fields.strip(),'let timestamp: Date\n    let kind: Kind')
