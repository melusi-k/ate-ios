"""Source/ledger/inverse checks only. These do not qualify native Swift."""
from pathlib import Path
import hashlib,json,re,unittest
from sync_payload_overflow_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class SyncPayloadOverflowPreflight(unittest.TestCase):
    def test_exact_inverse_refuses_missing_duplicate_or_unrelated_delta(self):
        for path,c in json.loads((ROOT/'scripts/tests/sync_payload_overflow_inverse.json').read_text()).items():
            source=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,source).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for mutation in [source.replace(f['new'],'',1),source+f['new'],source+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,mutation)
    def test_untrusted_numeric_preflight_precedes_first_recipe_decode(self):
        source=(ROOT/'Ate/Logic/SyncPayloadSafety.swift').read_text()
        first_decode=source.index('decoder.decode(RecipeCard.self')
        prefix=source[:first_decode]
        self.assertIn('number.isFinite, number >= 0, number < Double(Int.max)',prefix)
        self.assertIn('permitsUnknown && core.servings == 0',source)
        self.assertIn('number.isFinite, number > 0, number < Double(Int.max)',source[first_decode:])
    def test_legacy_integer_conversion_has_finite_and_both_bounds(self):
        source=(ROOT/'Ate/Models/Models.swift').read_text()
        helper=source.split('func legacyInteger(',1)[1].split('servings = try legacyInteger',1)[0]
        self.assertLess(helper.index('c.decode(Int.self'),helper.index('c.decode(Double.self'))
        self.assertLess(helper.index('number.isFinite, number >= Double(Int.min), number < Double(Int.max)'),helper.index('return Int(number)'))
        self.assertIn('throw DecodingError.dataCorruptedError',helper)
        self.assertNotIn('servings = Int(d)',source);self.assertNotIn('timeMinutes = Int(d)',source)
    def test_native_original_assertions_and_boundary_methods_are_required(self):
        source=(ROOT/'AteTests/SyncPayloadSafetyTests.swift').read_text()
        manifest=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        names=['testMalformedIdentityArraysNumbersAndFutureVersionFailClosed','testEachNumericOverflowRowFailsClosedWithoutTrapping','testOnlyEditableDraftsPermitZeroServingsAndNeverZeroTimeOrOverflow','testRecipeDecoderRejectsOutOfRangeDoublesButKeepsLegacyNumbers']
        for name in names:
            self.assertIn('func '+name+'(',source)
            self.assertEqual(manifest.count('SyncPayloadSafetyTests/'+name),1)
        self.assertIn('.init(count: invalid.count)',source)
        self.assertIn('Double(Int.max).nextDown',source)
        self.assertIn('XCTAssertEqual(bounds.servings, Int.max)',source)
        self.assertIn('XCTAssertEqual(bounds.timeMinutes, Int.min)',source)
        self.assertIn('draft.source = .appleIntelligence; draft.suggestionDraft = true',source)
