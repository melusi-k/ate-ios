from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
INSERTIONS={'Ate/Services/CookPlanNotifications.swift': ['        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 30)\n        #endif\n', '        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 31)\n        #endif\n', '        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 32, remaining.isDisjoint(with: ids) ? 0 : 1)\n        #endif\n', '        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 26)\n        #endif\n'], 'Ate/Views/CookPlanSheet.swift': ['                        #if DEBUG\n                        .modifier(FailureBoundaryReceipt(surface: .cookPlan))\n                        #endif\n', '            #if DEBUG\n            .onDisappear { FailureBoundaryDiagnostic.record(.cookPlan, 29) }\n            #endif\n', '        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 27)\n        #endif\n', '            #if DEBUG\n            FailureBoundaryDiagnostic.record(.cookPlan, 28, existing == nil ? 0 : 1)\n            #endif\n', '        #if DEBUG\n        FailureBoundaryDiagnostic.record(.cookPlan, 20)\n        #endif\n', '                #if DEBUG\n                FailureBoundaryDiagnostic.record(.cookPlan, 21)\n                #endif\n', '                #if DEBUG\n                FailureBoundaryDiagnostic.record(.cookPlan, 22)\n                #endif\n', '                #if DEBUG\n                FailureBoundaryDiagnostic.record(.cookPlan, 23)\n                #endif\n', '                #if DEBUG\n                FailureBoundaryDiagnostic.record(.cookPlan, 24)\n                #endif\n', '                #if DEBUG\n                FailureBoundaryDiagnostic.record(.cookPlan, 25)\n                #endif\n'], 'Ate/Views/NutritionDiaryView.swift': ['        #if DEBUG\n        .onAppear {\n            FailureBoundaryDiagnostic.record(.keyboard, 10, focusedField == nil ? 0 : (focusedField == "foodName" ? 1 : 2), foodName.count)\n        }\n        .onChange(of: focusedField) { _, field in\n            FailureBoundaryDiagnostic.record(.keyboard, 11, field == nil ? 0 : (field == "foodName" ? 1 : 2), foodName.count)\n        }\n        #endif\n', '                    #if DEBUG\n                    .modifier(FailureBoundaryReceipt(surface: .keyboard))\n                    #endif\n'], 'Ate/Views/RecipeDetailView.swift': ['                            #if DEBUG\n                            .modifier(FailureBoundaryReceipt(surface: .cookPlan))\n                            .onChange(of: planning) { _, value in\n                                FailureBoundaryDiagnostic.record(.cookPlan, 40, value ? 1 : 0)\n                            }\n                            #endif\n'], 'AteUITests/CookPlanUITests.swift': ['        app.launchArguments += ["-qaCookPlanCancelDiagnostic"]\n', '        captureCancelReceipt(app, "after-original-cancel-tap")\n', '        captureCancelReceipt(app, "before-original-final-assertion")\n', '\nextension CookPlanUITests {\n    private func captureCancelReceipt(_ app: XCUIApplication, _ phase: String) {\n        let editor = app.buttons["cookPlan.save"]\n        let detail = app.buttons["recipe.plan"]\n        let value: String?\n        if editor.exists { value = editor.value as? String }\n        else if detail.exists { value = detail.value as? String }\n        else { value = nil }\n        let body = "COOK-PLAN-CANCEL-RECEIPT phase=\\(phase) " + (value ?? "receipt-unavailable")\n        print(body)\n        let attachment = XCTAttachment(string: body)\n        attachment.name = "cook-plan-cancel-receipt-" + phase\n        attachment.lifetime = .keepAlways\n        add(attachment)\n    }\n}\n'], 'AteUITests/NutritionDiaryUITests.swift': ['    private var keyboardDiagnosticApp: XCUIApplication?\n    override func tearDown() {\n        if let app = keyboardDiagnosticApp, app.state == .runningForeground {\n            captureFailureBoundary(app.buttons["nutritionDiary.save"], phase: "before-teardown")\n        }\n        keyboardDiagnosticApp = nil\n        super.tearDown()\n    }\n', '        if app.launchArguments.contains("-qaDiaryKeyboardDiagnostic") {\n            captureFailureBoundary(app.buttons["nutritionDiary.save"], phase: "before-original-keyboard-assertion")\n        }\n', '        app.launchArguments += ["-qaDiaryKeyboardDiagnostic"]\n        keyboardDiagnosticApp = app\n', '\nextension NutritionDiaryUITests {\n    private func captureFailureBoundary(_ element: XCUIElement, phase: String) {\n        let value = element.exists ? element.value as? String : nil\n        let body = "DIARY-KEYBOARD-RECEIPT phase=\\(phase) " + (value ?? "receipt-unavailable")\n        print(body)\n        let attachment = XCTAttachment(string: body)\n        attachment.name = "diary-keyboard-receipt-" + phase\n        attachment.lifetime = .keepAlways\n        add(attachment)\n    }\n}\n']}
HASHES={'Ate/Services/CookPlanNotifications.swift': '4948a4701ea465790e97d29a357d76e08d9031c25ca865aa051809aa1e1c2c55', 'Ate/Views/CookPlanSheet.swift': '75fb68558b403342dcbd9d790c48e16410c2b1122f52fa93c020b8de6c182d9e', 'Ate/Views/NutritionDiaryView.swift': 'bb7193b0629209102a368441491ff25400d21df4daa6ca18007787c2bbcbff6c', 'Ate/Views/RecipeDetailView.swift': 'ce7359e74215f4fef7bec6191cbbc95fc5c20f77f868bcf43e5c4f85ee1ea24b', 'AteUITests/CookPlanUITests.swift': '73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec', 'AteUITests/NutritionDiaryUITests.swift': 'b7c4abfb5f3dfc4e74783d682aea2ab2023c71fb226c1a7cb6d040ce311ba484'}
HELPER_HASH='6c5166155518c0c89d3e13a00562f10e6c3a27427d92a14bcc7e5c3dd5ff22bf'
def before_failure_receipts(path, source):
    for block in INSERTIONS[path]:
        if source.count(block)!=1: raise AssertionError("Missing/changed/duplicated diagnostic block: "+path)
        source=source.replace(block,"",1)
    return source

class FailureBoundaryDiagnosticTests(unittest.TestCase):
    def test_exact_hosted_parent_reconstructed(self):
        for path,h in HASHES.items():
            self.assertEqual(hashlib.sha256(before_failure_receipts(path,(ROOT/path).read_text()).encode()).hexdigest(),h)
        self.assertEqual(hashlib.sha256((ROOT/"Ate/App/FailureBoundaryDiagnostic.swift").read_bytes()).hexdigest(),HELPER_HASH)

    def test_exact_inverse_rejects_missing_duplicated_or_changed_blocks(self):
        for path,blocks in INSERTIONS.items():
            source=(ROOT/path).read_text()
            for block in blocks:
                changed=block.replace(next(c for c in block if c.isalpha()),"Z",1)
                for mutant in (source.replace(block,"",1),source.replace(block,block+block,1),source.replace(block,changed,1)):
                    with self.assertRaises(AssertionError):before_failure_receipts(path,mutant)

    def test_native_assertion_wait_and_input_mutants_still_fail(self):
        path="AteUITests/NutritionDiaryUITests.swift";s=(ROOT/path).read_text()
        for a,b in [('timeout: 5), "Keyboard should appear','timeout: 50), "Keyboard should appear'),('element.typeText(text)','element.typeText("substitute")')]:
            self.assertIn(a,s)
            self.assertNotEqual(hashlib.sha256(before_failure_receipts(path,s.replace(a,b,1)).encode()).hexdigest(),HASHES[path])
        path="AteUITests/CookPlanUITests.swift";s=(ROOT/path).read_text()
        a='XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)'
        self.assertIn(a,s)
        self.assertNotEqual(hashlib.sha256(before_failure_receipts(path,s.replace(a,'XCTAssertTrue(true)',1)).encode()).hexdigest(),HASHES[path])

    def test_numeric_rings_bounded_and_flags_required(self):
        s=(ROOT/"Ate/App/FailureBoundaryDiagnostic.swift").read_text()
        for a in ['#if DEBUG','AppConfig.isUITesting','-qaDiaryKeyboardDiagnostic','-qaCookPlanCancelDiagnostic','count < 32','keyboardWillShowNotification','keyboardDidHideNotification','accessibilityValue']:
            self.assertIn(a,s)
        for a in ['Timer(','.asyncAfter','sleep(','firstResponder','hasKeyboardFocus','UserDefaults','recipeID','foodName','query']:
            self.assertNotIn(a,s)
        for path,blocks in INSERTIONS.items():
            if path.startswith('AteUITests/'):
                new=''.join(blocks)
                for forbidden in ['typeText(','.tap()', 'waitForExistence(', 'waitForNonExistence(', 'XCTAssert', 'Thread.sleep']:
                    self.assertNotIn(forbidden,new)

    def test_receipt_is_retained_before_original_assertions(self):
        s=(ROOT/"AteUITests/NutritionDiaryUITests.swift").read_text()
        self.assertLess(s.index('phase: "before-original-keyboard-assertion"'),s.index('"Keyboard should appear for the focused field"'))
        s=(ROOT/"AteUITests/CookPlanUITests.swift").read_text()
        self.assertLess(s.index('captureCancelReceipt(app, "before-original-final-assertion")'),s.index('XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)'))
        for path in ['AteUITests/CookPlanUITests.swift','AteUITests/NutritionDiaryUITests.swift']:
            s=''.join(INSERTIONS[path]);self.assertIn('.keepAlways',s);self.assertIn('print(body)',s)
