"""Diagnostic-only #550. Native behavior and screenshot acceptance remain UNRUN."""
from pathlib import Path
import hashlib,json,unittest
from account_550_diagnostic_delta import restore,FIXTURE
ROOT=Path(__file__).resolve().parents[2]
class Account550Diagnostic(unittest.TestCase):
    def test_exact_additive_inverse_and_mutants(self):
        for file,spec in json.loads(FIXTURE.read_bytes()).items():
            raw=(ROOT/file).read_text()
            self.assertEqual(hashlib.sha256(restore(file,raw).encode()).hexdigest(),spec['base_sha256'])
            for new,old in spec['inverse']:
                for changed in [raw.replace(new,'',1),raw+new]:
                    with self.assertRaises(AssertionError):restore(file,changed)
    def test_shopping_failed_terms_only_after_unchanged_wait(self):
        ui=(ROOT/'AteUITests/ShoppingSyncCaptureUITests.swift').read_text()
        block=ui.split('let initialReadyResult = ',1)[1].split('let synced = ',1)[0]
        self.assertIn('predicate: ready, object: refresh)], timeout: 10)',block)
        self.assertLess(block.index('timeout: 10)'),block.index('if initialReadyResult != .completed'))
        self.assertLess(block.index('refreshDiagnostics("pre-refresh-ready-failure"'),block.index('XCTAssertEqual(initialReadyResult, .completed)'))
    def test_export_trace_guarded_no_data_and_collected(self):
        ui=(ROOT/'Ate/Views/SettingsView.swift').read_text()
        helper=ui.split('private func exportDiagnostic(',1)[1].split('private func importSelectedData()',1)[0]
        self.assertIn('guard AppConfig.isUITesting else { return }',helper)
        self.assertIn('privacy: .public',helper)
        for forbidden in ['items','url','data','account','Task','sleep','activeSheet =']:
            self.assertNotIn(forbidden,helper)
        self.assertLess(ui.index('exportDiagnostic("action-entered")'),ui.index('guard !exporting'))
        self.assertLess(ui.index('activeSheet = .share('),ui.index('exportDiagnostic("share-state-set")'))
        workflow=(ROOT/'.github/workflows/compile-check.yml').read_text()
        self.assertIn("category == \"settings-export-diagnostic\"",workflow)
        self.assertIn('> settings-export-diagnostic.log 2>&1',workflow)
        self.assertIn('            *.log',workflow)
    def test_export_native_assertions_tap_and_budget_entire_file_frozen(self):
        self.assertEqual(hashlib.sha256((ROOT/'AteUITests/CoverageUITests.swift').read_bytes()).hexdigest(),'4aa3c2cc1c494994b13e3f3e8bb36a1067b744847c0b694034425b0f0b179cf8')
