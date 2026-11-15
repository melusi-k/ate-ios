from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class TabCollectionRetentionTests(unittest.TestCase):
    def test_tab_binding_uses_distinct_state_transition(self):
        root=(ROOT/'Ate/App/AteApp.swift').read_text().split('var tabSelection: Binding<AppTab>',1)[1].split('\n    }',1)[0]
        self.assertIn('store.selectTab(new)',root)
        self.assertNotIn('store.select(new)',root)
        store=(ROOT/'Ate/Store/AppStore.swift').read_text()
        self.assertIn('if t == .library { tab = t }',store)
        self.assertIn('case .library: filter.collection = nil; tab = t',store)
    def test_original_explore_native_assertions_untouched(self):
        source=(ROOT/'AteUITests/ExploreUITests.swift').read_text()
        source=source.replace(', "-qaSearchFocusDiagnostic"','')
        source=source.replace('    override func tearDown() {\n        if name.contains("testExploreDismissPreservesCollectionAndSearchQuery") {\n            shot("explore-search-focus-before-teardown-termination")\n        }\n        XCUIDevice.shared.orientation = .portrait; app.terminate()\n    }','    override func tearDown() { XCUIDevice.shared.orientation = .portrait; app.terminate() }')
        source=source.replace('        var diagnosticEvaluations = 0\n        let readyForInput = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in\n            let began = ProcessInfo.processInfo.systemUptime\n            if diagnosticEvaluations < 20 {\n                print("SEARCH-FOCUS-PREDICATE-START evaluation=\\(diagnosticEvaluations + 1) uptime=\\(began)")\n            }\n            var focused: Bool? = nil\n            var keyboardPresent: Bool? = nil\n            defer {\n                if diagnosticEvaluations < 20 {\n                    diagnosticEvaluations += 1\n                    print("SEARCH-FOCUS-PREDICATE evaluation=\\(diagnosticEvaluations) start=\\(began) end=\\(ProcessInfo.processInfo.systemUptime) focus=\\(focused.map { $0 ? 1 : 0 } ?? -1) keyboard=\\(keyboardPresent.map { $0 ? 1 : 0 } ?? -1)")\n                }\n            }\n            guard let field = object as? XCUIElement,\n                  field.responds(to: focusSelector) else { return false }\n            focused = field.value(forKey: "hasKeyboardFocus") as? Bool\n            guard focused == true else { return false }\n            keyboardPresent = keyboard.exists\n            return keyboardPresent == true\n        }, object: search)','        let readyForInput = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in\n            guard let field = object as? XCUIElement,\n                  field.responds(to: focusSelector),\n                  (field.value(forKey: "hasKeyboardFocus") as? Bool) == true else { return false }\n            return keyboard.exists\n        }, object: search)')
        source=source.replace('        shot("explore-search-focus-after-original-predicate")\n','')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),'94b46cdbca8d0e61072956792061874b76f15ec06ee61942d850657d7eb5fc72')
