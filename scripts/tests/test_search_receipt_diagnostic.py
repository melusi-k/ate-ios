from approved_merge_536 import normalize
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
HELPER='\n#if DEBUG\n/// Opt-in numeric binding receipt only. No query text, focus or AX reads.\n@MainActor enum SearchReceiptDiagnostic {\n    static var enabled: Bool {\n        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaSearchFocusDiagnostic")\n    }\n    private static var events = 0\n    private static var rows: [String] = []\n    static func begin(previous: Int, incoming: Int) -> Int? {\n        guard enabled, events < 8 else { return nil }\n        events += 1\n        record(phase: 1, event: events, first: Double(previous), second: Double(incoming))\n        return events\n    }\n    static func end(event: Int?, stored: Int) {\n        guard let event else { return }\n        record(phase: 2, event: event, first: Double(stored), second: 0)\n        let scheduled = ProcessInfo.processInfo.systemUptime\n        DispatchQueue.global(qos: .utility).async {\n            let utility = ProcessInfo.processInfo.systemUptime\n            Task { @MainActor in\n                record(phase: 3, event: event, first: scheduled, second: utility)\n            }\n        }\n    }\n    private static func record(phase: Int, event: Int, first: Double, second: Double) {\n        guard rows.count < 24,\n              let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }\n        rows.append("pid=\\(ProcessInfo.processInfo.processIdentifier) phase=\\(phase) event=\\(event) uptime=\\(ProcessInfo.processInfo.systemUptime) first=\\(first) second=\\(second)")\n        do {\n            try Data((rows.joined(separator: "\\n") + "\\n").utf8).write(to: cache.appendingPathComponent("search-receipt-diagnostic.txt"), options: .atomic)\n        } catch {\n            Logger(subsystem: "com.melusik.ate", category: "SearchReceiptDiagnostic").error("Search receipt numeric evidence write failed")\n        }\n    }\n}\n#endif\n'
IMPORTS='#if DEBUG\nimport OSLog\n#endif\n'
OLD='    private var queryBinding: Binding<String> { searchPlacement == .tabBar ? $searchQuery : $libraryQuery }'
BINDING='    private var queryBinding: Binding<String> {\n        let original = searchPlacement == .tabBar ? $searchQuery : $libraryQuery\n#if DEBUG\n        if searchPlacement == .tabBar && SearchReceiptDiagnostic.enabled {\n            return Binding(get: { original.wrappedValue }, set: { value in\n                let event = SearchReceiptDiagnostic.begin(previous: original.wrappedValue.count, incoming: value.count)\n                original.wrappedValue = value\n                SearchReceiptDiagnostic.end(event: event, stored: original.wrappedValue.count)\n            })\n        }\n#endif\n        return original\n    }'
WORKFLOW='            if [ -f "$data_container/Library/Caches/search-receipt-diagnostic.txt" ]; then\n              cp "$data_container/Library/Caches/search-receipt-diagnostic.txt" "$RUNNER_TEMP/explore-evidence/search-receipt-diagnostic.txt"\n            else\n              echo \'Receipt file missing; binding delivery unverified.\' > "$RUNNER_TEMP/explore-evidence/receipt-missing.txt"\n            fi\n'
class SearchReceiptTests(unittest.TestCase):
    def test_exact_original_library_and_workflow_reconstruct(self):
        source=normalize('main:Ate/Views/LibraryView.swift', (ROOT/'Ate/Views/LibraryView.swift').read_text())
        for new,old in [(IMPORTS,''),(BINDING,OLD),(HELPER,'')]:
            self.assertEqual(source.count(new),1)
            source=source.replace(new,old,1)
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), 'dded325b47238833a7fd993cafbc8f5f9c03ab2daa896af4466d240651bfd5d1')
        workflow=normalize('main:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text())
        self.assertEqual(workflow.count(WORKFLOW),1)
        self.assertEqual(hashlib.sha256(workflow.replace(WORKFLOW,'',1).encode()).hexdigest(), 'bd947a85e736a87bdc887475e0908050e4f8718f2314b34ce5cb07b03ea871c3')
    def test_native_input_contract_entire_file_unchanged(self):
        self.assertEqual(hashlib.sha256(normalize('main:AteUITests/ExploreUITests.swift', (ROOT/'AteUITests/ExploreUITests.swift').read_bytes())).hexdigest(), '5e300bda3a3f8ab02caae977a6d3906f0d1df4700b11d29cbbb443af6fcf1b25')
    def test_numeric_opt_in_bounded_no_polling_or_query_text(self):
        for token in ['AppConfig.isUITesting','-qaSearchFocusDiagnostic','events < 8','rows.count < 24','original.wrappedValue = value']:
            self.assertIn(token,HELPER+BINDING)
        for token in ['Timer(', 'sleep(', 'asyncAfter', 'hasKeyboardFocus', 'firstResponder', 'miso', '.exists']:
            self.assertNotIn(token,HELPER)
