from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class LiveActivityDiagnosticRefreshTests(unittest.TestCase):
    def test_candidate_removes_only_automatic_timer(self):
        removed='        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }\n'
        source=(ROOT/'Ate/Views/MoreView.swift').read_text()
        self.assertNotIn(removed,source)
        anchor='        .id(tick)\n'
        self.assertEqual(source.count(anchor),1)
        restored=source.replace(anchor,anchor+removed,1)
        self.assertEqual(restored.count(removed),1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), '883f4dff8173af951661c5298d62b3720d6bf69305b2c51ab9a5714b0e30978a')
        self.assertIn('Button("Refresh") { tick += 1 }',source)
