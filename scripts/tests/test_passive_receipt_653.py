"""Diagnostic-only change: no remote property reads or acceptance changes."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PassiveReceiptTests(unittest.TestCase):
    def test_journeys_assertions_workflow_and_project_remain_exact(self):
        pins = json.loads((ROOT / 'scripts/tests/passive_receipt_653_source_pins.json').read_text())
        for path, digest in pins.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)

    def test_inspection_never_dereferences_or_describes_remote_element(self):
        helper = (ROOT / 'AteUITests/NamedRedReceipt.swift').read_text()
        inspect = helper[helper.index('    func inspect('):]
        self.assertIn('_: XCUIElement, capturedValues: String? = nil', inspect)
        self.assertIn('step("inspect-\\(name)")', inspect)
        self.assertIn('capture=phase-only', inspect)
        self.assertIn('if let capturedValues', inspect)
        self.assertIn('values=\\(capturedValues)', inspect)
        for token in ['.exists', '.frame', '.identifier', '.label', '.debugDescription',
                      'waitFor', '.snapshot', 'screenshot', 'String(describing:', 'String(reflecting:']:
            self.assertNotIn(token, inspect)
