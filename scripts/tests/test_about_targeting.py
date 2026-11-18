from approved_merge_composed import normalize
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
def restore_about_targeting(test,s):
    test.assertIn('func scrollTo(_ e: XCUIElement, max: Int = 25, searchDownFirst: Bool = true, surface: XCUIElement? = nil) {',s)
    s=s.replace('func scrollTo(_ e: XCUIElement, max: Int = 25, searchDownFirst: Bool = true, surface: XCUIElement? = nil) {','func scrollTo(_ e: XCUIElement, max: Int = 25, searchDownFirst: Bool = true) {')
    test.assertIn('(surface ?? app).swipeUp()',s)
    s=s.replace('(surface ?? app).swipeUp()','app.swipeUp()')
    test.assertIn('(surface ?? app).swipeDown()',s)
    s=s.replace('(surface ?? app).swipeDown()','app.swipeDown()')
    test.assertIn('scrollTo(settingsQuietHours, searchDownFirst: false, surface: timerSettings)',s)
    s=s.replace('scrollTo(settingsQuietHours, searchDownFirst: false, surface: timerSettings)','scrollTo(settingsQuietHours, searchDownFirst: false)')
    test.assertIn('scrollTo(settingsStepAlerts, surface: timerSettings);',s)
    s=s.replace('scrollTo(settingsStepAlerts, surface: timerSettings);','scrollTo(settingsStepAlerts);')
    test.assertEqual(s.count('        let about = timerSettings.staticTexts["aboutVersion"]; revealReadOnlySettingsRow(about); wait(about, 3)\n        XCTAssertTrue(about.label.contains("(build "))\n'),1)
    s=s.replace('        let about = timerSettings.staticTexts["aboutVersion"]; revealReadOnlySettingsRow(about); wait(about, 3)\n        XCTAssertTrue(about.label.contains("(build "))\n',"",1)
    s=s.replace('        // The SwiftUI combined container is not consistently hittable across simulator\n','        let about = timerSettings.staticTexts["aboutVersion"]; scrollTo(about); wait(about, 3)\n        XCTAssertTrue(about.label.contains("(build "))\n        // The SwiftUI combined container is not consistently hittable across simulator\n',1)
    return s

class AboutTargetingTests(unittest.TestCase):
    def test_every_original_line_preserved_except_targeting(self):
        from test_relay_return_capture import restore_relay_return_capture
        source=restore_relay_return_capture(self,normalize('source:AteUITests/CoverageUITests.swift', (ROOT/"AteUITests/CoverageUITests.swift").read_text()),'AteUITests/CoverageUITests.swift')
        s=restore_about_targeting(self,source)
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'0abc3487edc256853e0edc5843c620c58839085dbf16b3b6c6210831e8959b97')
