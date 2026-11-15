from test_search_live_receipt_diagnostic import original_source
from pathlib import Path
import unittest,hashlib,yaml,subprocess
ROOT=Path(__file__).resolve().parents[2]
class SearchFocusDiagnosticTests(unittest.TestCase):
    def test_original_entire_ui_reconstructs(self):
        s=(ROOT/'AteUITests/ExploreUITests.swift').read_text()
        s=original_source('AteUITests/ExploreUITests.swift',s)
        replacements=[(', "-qaSearchFocusDiagnostic"', ''), ('    override func tearDown() {\n        if name.contains("testExploreDismissPreservesCollectionAndSearchQuery") {\n            shot("explore-search-focus-before-teardown-termination")\n        }\n        XCUIDevice.shared.orientation = .portrait; app.terminate()\n    }', '    override func tearDown() { XCUIDevice.shared.orientation = .portrait; app.terminate() }'), ('        var diagnosticEvaluations = 0\n        let readyForInput = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in\n            let began = ProcessInfo.processInfo.systemUptime\n            if diagnosticEvaluations < 20 {\n                print("SEARCH-FOCUS-PREDICATE-START evaluation=\\(diagnosticEvaluations + 1) uptime=\\(began)")\n            }\n            var focused: Bool? = nil\n            var keyboardPresent: Bool? = nil\n            defer {\n                if diagnosticEvaluations < 20 {\n                    diagnosticEvaluations += 1\n                    print("SEARCH-FOCUS-PREDICATE evaluation=\\(diagnosticEvaluations) start=\\(began) end=\\(ProcessInfo.processInfo.systemUptime) focus=\\(focused.map { $0 ? 1 : 0 } ?? -1) keyboard=\\(keyboardPresent.map { $0 ? 1 : 0 } ?? -1)")\n                }\n            }\n            guard let field = object as? XCUIElement,\n                  field.responds(to: focusSelector) else { return false }\n            focused = field.value(forKey: "hasKeyboardFocus") as? Bool\n            guard focused == true else { return false }\n            keyboardPresent = keyboard.exists\n            return keyboardPresent == true\n        }, object: search)', '        let readyForInput = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in\n            guard let field = object as? XCUIElement,\n                  field.responds(to: focusSelector),\n                  (field.value(forKey: "hasKeyboardFocus") as? Bool) == true else { return false }\n            return keyboard.exists\n        }, object: search)'), ('        shot("explore-search-focus-after-original-predicate")\n', '')]
        for a,b in replacements:
            self.assertEqual(s.count(a),1)
            s=s.replace(a,b)
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'94b46cdbca8d0e61072956792061874b76f15ec06ee61942d850657d7eb5fc72')
    def test_notification_only_and_bounded(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text().split('@MainActor enum SearchFocusDiagnostic {')[1]
        for token in ['rows.count < 20','-qaSearchFocusDiagnostic','AppConfig.isUITesting','keyboardWillShowNotification','keyboardDidShowNotification','keyboardWillHideNotification','keyboardDidHideNotification','.atomic']:
            self.assertIn(token,s)
        for token in ['firstResponder','hasKeyboardFocus','store.','Task.sleep','Timer(']:self.assertNotIn(token,s)
        w=yaml.safe_load((ROOT/'.github/workflows/compile-check.yml').read_text())
        for j in w['jobs'].values():
            for step in j.get('steps',[]):
                if 'focus-copy-utc' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True)
                    self.assertEqual(p.returncode,0,p.stderr)
