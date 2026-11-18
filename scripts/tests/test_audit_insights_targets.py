"""Source-only audit regression. Native pixels/AX remain UNRUN."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AuditSlice(unittest.TestCase):
    def test_authorized_source_change(self):
        s=(ROOT/'Ate/Views/InsightsView.swift').read_text()
        self.assertIn('withAnimation(Motion.anim(.snappy)) { isEditingInsightOrder.toggle() }',s)
        self.assertIn('HStack(spacing: 12)',s)
        for symbol in ['arrow.up','arrow.down']:
            self.assertIn('Image(systemName: "'+symbol+'").frame(width: 44, height: 44).contentShape(Rectangle())',s)
        self.assertNotIn('withAnimation(.snappy)',s)
