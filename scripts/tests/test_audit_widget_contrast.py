"""Source-only audit regression. Native pixels/AX remain UNRUN."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AuditSlice(unittest.TestCase):
    def test_authorized_source_change(self):
        s=(ROOT/'AteWidgets/HomeWidgets.swift').read_text()
        tile=s.split('private struct CookingWidgetView',1)[1].split('// MARK: Tonight',1)[0]
        self.assertNotIn('foregroundStyle(WTheme.primary)',tile)
        self.assertEqual(tile.count('foregroundStyle(WTheme.brown)'),4)
        def lum(h):
            rgb=[int(h[i:i+2],16)/255 for i in (0,2,4)]
            return sum(w*(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4) for v,w in zip(rgb,[.2126,.7152,.0722]))
        self.assertGreaterEqual((lum('F5E2C0')+.05)/(lum('512E1A')+.05),4.5)
        self.assertIn('static let cream = Color(red: 0xF5 / 255, green: 0xE2 / 255, blue: 0xC0 / 255)',s)
        self.assertIn('static let brown = Color(red: 0x51 / 255, green: 0x2E / 255, blue: 0x1A / 255)',s)
