from pathlib import Path
import subprocess, unittest
ROOT=Path(__file__).resolve().parents[2]
HELPER='    /// Opt-in diagnostic reads can perturb AX timing; never retry or navigate here.\n    func captureJournalTabMetrics(_ phase: String) {\n#if DEBUG\n        guard app.launchArguments.contains("-UITesting"),\n              app.launchArguments.contains("-qaJournalTabMetrics") else { return }\n        let start = Date()\n        var rows = ["phase=\\(phase) timingPerturbingAXReads=true"]\n        for name in ["Library", "Shopping", "Journal", "Settings", "Search"] {\n            let button = app.tabBars.buttons[name]\n            let exists = button.exists\n            if exists {\n                let frame = button.frame\n                let selected = button.isSelected\n                let hittable = button.isHittable\n                rows.append("tab=\\(name) exists=true selected=\\(selected) hittable=\\(hittable) frame=\\(frame) elapsed=\\(Date().timeIntervalSince(start))")\n            } else {\n                rows.append("tab=\\(name) exists=false elapsed=\\(Date().timeIntervalSince(start))")\n            }\n        }\n        let attachment = XCTAttachment(string: rows.joined(separator: "\\n"))\n        attachment.name = "journal-tab-metrics-\\(phase)"\n        attachment.lifetime = .keepAlways\n        add(attachment)\n#endif\n    }\n'
class JournalTabMetricsTests(unittest.TestCase):
    def test_capture_only_all_original_coverage_preserved(self):
        original=subprocess.check_output(['git','show','bc45b9588799da4eb1c603eb9e6dfe28e5918ed4:AteUITests/CoverageUITests.swift'],cwd=ROOT,text=True)
        current=(ROOT/'AteUITests/CoverageUITests.swift').read_text()
        for fragment in [HELPER, '            captureJournalTabMetrics("before-hittable-waiter")\n', '        captureJournalTabMetrics("after-selected-settings-reveal")\n']:
            self.assertEqual(current.count(fragment),1)
            current=current.replace(fragment,'',1)
        current=current.replace('launch(["-qaJournalTabMetrics"])','launch()')
        self.assertEqual(current,original)
    def test_capture_is_debug_and_opt_in_ui_testing(self):
        self.assertIn('#if DEBUG',HELPER)
        self.assertIn('contains("-UITesting")',HELPER)
        self.assertIn('contains("-qaJournalTabMetrics")',HELPER)
        self.assertNotIn('.tap()',HELPER)
        self.assertNotIn('waitFor',HELPER)
        self.assertNotIn('sleep(',HELPER)
        self.assertNotIn('while ',HELPER)
        self.assertIn('button.isHittable',HELPER)
