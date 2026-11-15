from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[2]
class LiveActivityDiagnosticRefreshTests(unittest.TestCase):
    def test_candidate_removes_only_automatic_timer(self):
        baseline=subprocess.check_output(['git','show','5099f06e0a316d80add93c6d22d9c57454dd81db:Ate/Views/MoreView.swift'],cwd=ROOT,text=True)
        removed='        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }\n'
        self.assertEqual(baseline.count(removed),1)
        source=(ROOT/'Ate/Views/MoreView.swift').read_text()
        self.assertEqual(source,baseline.replace(removed,''))
        self.assertIn('Button("Refresh") { tick += 1 }',source)
