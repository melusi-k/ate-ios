"""#414 bounded layout source guard; native pixels still required."""
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class CoverControlLabelContracts(unittest.TestCase):
    def test_wrap_layout_keeps_all_actions_at_intrinsic_width(self):
        s=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text().split('private func coverEditor(',1)[1].split('private func setUserCover',1)[0]
        self.assertIn('WrapLayout(spacing: 8)',s)
        self.assertNotIn('HStack(spacing: 8)',s)
        self.assertEqual(s.count('.fixedSize(horizontal: true, vertical: false)'),4)
        self.assertIn('.lineLimit(1)',s)
        for action in ['changeCover','sampleCover','generateCover','removeCover']:
            self.assertEqual(s.count('.accessibilityIdentifier("'+action+'")'),1)
    def test_exact_parent_sheet_reconstructs(self):
        s=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        before,rest=s.split('    @ViewBuilder private func coverEditor(',1)
        part,after=rest.split('\n    private func setUserCover',1)
        part=part.replace('WrapLayout(spacing: 8)','HStack(spacing: 8)',1)
        self.assertEqual(part.count('.fixedSize(horizontal: true, vertical: false)'),4)
        import re
        part=re.sub(r'\n +\.fixedSize\(horizontal: true, vertical: false\)','',part)
        part=part.replace('\n            .lineLimit(1)','',1)
        restored=before+'    @ViewBuilder private func coverEditor('+part+'\n    private func setUserCover'+after
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),'41f185e2fc4ede4e7dcb32b93db5909b5b8bcd0ae3bd28948d71bd1b26ec2314')
    def test_original_photo_and_cover_cases_untouched(self):
        for file,digest in ORIGINALS.items():
            self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),digest,file)
    def test_new_case_retains_both_pixel_states(self):
        s=(ROOT/'AteUITests/CoverControlLabelUITests.swift').read_text()
        for token in ['cover-controls-normal-text-photo-unbroken-labels','cover-controls-normal-text-after-remove',
                      'XCTAssertFalse(earlier.intersects(button.frame)','XCTAssertGreaterThanOrEqual(button.frame.height, 44)']:
            self.assertIn(token,s)
ORIGINALS={'AteUITests/KeyFlowsQATests.swift': 'c07bdfa3a5a831f9fac67e546a6ab6607e73f141f7f6793cd8d1d6c6bb69d629', 'AteUITests/CoverageUITests.swift': '28357241b1a3afaadaeecb7ceb41bdb3e7deccc9f97fda2ba4646ac1b23b491f', 'AteTests/OCRTerminalResultTests.swift': 'da0d9653ef2a33928536320a3da3435160fa7318eb7cfc606937178616ed8816'}
