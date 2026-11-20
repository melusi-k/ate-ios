from pathlib import Path
import unittest,json,hashlib
from verified_heading_fix_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class VerifiedHeadingFix(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        for path,c in json.loads((ROOT/'scripts/tests/verified_heading_fix_inverse.json').read_text()).items():
            s=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,changed)
    def test_colon_is_not_required_for_for_or_to_and_native_case_is_required(self):
        source=(ROOT/'Ate/Logic/VerifiedPasteImport.swift').read_text()
        self.assertIn('if line.hasSuffix(":") && line.range',source)
        self.assertNotIn('if line.hasSuffix(":"), line.range',source)
        self.assertIn('VerifiedPasteHeadingTests/testColonlessForAndToHeadingsNeverConsumeAnIngredientSlot', (ROOT/'scripts/full-unit-required.txt').read_text().splitlines())
        tests=(ROOT/'AteTests/VerifiedPasteImportTests.swift').read_text()
        self.assertIn('XCTAssertEqual(card.ingredients.count, 28)',tests)
        self.assertIn('XCTAssertEqual(card.pastedSource?.writtenTime, "40-60 Minutes")',tests)
