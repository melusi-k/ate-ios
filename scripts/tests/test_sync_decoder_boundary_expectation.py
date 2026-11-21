"""Arithmetic/source-preservation evidence only, not Swift or native execution."""
from pathlib import Path
from decimal import Decimal
import hashlib
import json
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SyncDecoderBoundaryExpectationTests(unittest.TestCase):
    def test_decimal_spelling_and_binary_value_are_distinct_exact_integers(self):
        binary = math.nextafter(float(2**63 - 1), -math.inf)
        self.assertEqual(int(binary), 9_223_372_036_854_774_784)
        self.assertEqual(int(Decimal('9.223372036854775e+18')), 9_223_372_036_854_775_000)
        self.assertNotEqual(int(binary), int(Decimal('9.223372036854775e+18')))
        for literal in ['9.223372036854775e+18', '-9.223372036854775e+18']:
            exact = Decimal(literal)
            self.assertEqual(exact, exact.to_integral_value())
            self.assertLessEqual(-(2**63), int(exact))
            self.assertLess(int(exact), 2**63)

    def test_exact_inverse_preserves_all_other_numeric_contracts(self):
        fixture = ROOT / 'scripts/tests/sync_decoder_boundary_inverse.json'
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), FIXTURE_SHA)
        c = json.loads(fixture.read_text())
        s = (ROOT / 'AteTests/SyncPayloadSafetyTests.swift').read_text()
        self.assertEqual(s.count(c['new']), 1)
        restored = s.replace(c['new'], c['old'], 1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), c['parent_sha'])
        for token in ['XCTAssertEqual(nearLimit.servings, safeInteger)',
                      'XCTAssertEqual(nearLimit.timeMinutes, safeInteger)',
                      'XCTAssertEqual(exactDecimal.servings, expected',
                      'XCTAssertEqual(exactDecimal.timeMinutes, expected']:
            self.assertIn(token, c['new'])
        self.assertNotIn('XCTAssertNoThrow', c['new'])

FIXTURE_SHA = '7340fa04098fd125c90e47c3a9515c0fcfc772f7d55dd1556c93ea3d66f668b2'
