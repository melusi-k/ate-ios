"""#537 stacked-head regression: main:AddRecipeSheet.swift reversal is byte-exact.

The stacked #537 head adds the addRecipe.content identifier line. The composed
inverse fixture must remove exactly that line so the main-side reversal restores
the parent bytes, with nothing left over and no whitespace normalization."""
from pathlib import Path
import hashlib, unittest
from approved_merge_composed import normalize
ROOT=Path(__file__).resolve().parents[2]
KEY='main:Ate/Views/AddRecipeSheet.swift'
# sha256 of the stacked-parent file bytes: main 189d03a0 plus the stacked #544
# confidenceLabel hunk (byte-exact, verified against an independent reconstruction).
PARENT_SHA256='2ce0ea7f81d276112b42fcf3846d8d563a60e3badefc608a91809afead97212a'
IDENTIFIER='        .accessibilityIdentifier("addRecipe.content")\n'

class Merge537AddRecipeSheetInverseTests(unittest.TestCase):
    def test_reversal_restores_parent_bytes_exactly(self):
        text=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertEqual(text.count(IDENTIFIER),1)
        restored=normalize(KEY,text)
        self.assertNotIn(IDENTIFIER,restored)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),PARENT_SHA256)
    def test_missing_or_duplicated_identifier_fragment_fails(self):
        text=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        for changed in (text.replace(IDENTIFIER,'',1), text.replace(IDENTIFIER,IDENTIFIER+IDENTIFIER,1)):
            with self.assertRaises(AssertionError):
                normalize(KEY,changed)
