"""Source-only audit regression. Native pixels/AX remain UNRUN."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AuditSlice(unittest.TestCase):
    def test_authorized_source_change(self):
        s=(ROOT/'Ate/Views/ShoppingListView.swift').read_text()
        action=s.split('Button("Sync now")',1)[1].split('.accessibilityIdentifier("shopping.syncNow")',1)[0]
        self.assertIn('Task { await store.syncNow() }',action)
        self.assertIn('.frame(minWidth: 44, minHeight: 44)',action)
        self.assertIn('.contentShape(Rectangle())',action)
        self.assertIn('.disabled(store.syncState == .syncing)',action)
