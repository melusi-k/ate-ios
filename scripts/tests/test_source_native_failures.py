"""Source guards for #600 failures exposed by #601. Not native qualification."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
OLD_CASES = [
    'MultiPartPastedRecipeContracts/testMultiPartKeepsFoodNounItemsWithMethodPresent',
    'PagePromptAndRegexContracts/testFinalPagePromptCarriesIngredientLinesPastTheOldCap',
    'PagePromptAndRegexContracts/testRegexPathsCompileAndMatch',
    'RecipeShapedFailClosedContracts/testASCIIFractionsAndMixedNumbersRoundTrip',
    'URLPageMultiPartContracts/testPageClippedBeforeTheRecipeNeverCertifies',
    'URLPageMultiPartContracts/testPageVerifiesWithAllComponents',
]
NEW_CASES = [
    'testExplicitSectionMethodsDoNotNeedThreeSocialCaptionKeywords',
    'testFractionPathsRunWithShortExplicitMethod',
    'testOnlyTerminalExactConversionWidgetPairIsOutsideTheList',
    'testIncompleteMultipartMethodFailsClosedAndCompleteMethodKeepsAllRows',
]


class SourceNativeFailurePreflight(unittest.TestCase):
    def test_sectioned_method_evidence_is_separate_from_caption_heuristic(self):
        source = (ROOT / 'Ate/Logic/SourceRecipeFidelity.swift').read_text()
        self.assertEqual(source.count('guard !method.isEmpty, hasStructuredMethod(method),'), 2)
        self.assertIn('private static func hasStructuredMethod(_ method: String) -> Bool', source)
        self.assertIn('guard !method.isEmpty, CaptionAnalysis.hasRecipeSignals(method) else', source)
        native = (ROOT / 'AteTests/SourceRecipeNativeRegressionTests.swift').read_text()
        self.assertIn('XCTAssertFalse(CaptionAnalysis.hasRecipeSignals(method)', native)
        self.assertIn('SourceRecipeFidelity.structuredRecipe(noAction)', native)

    def test_page_widget_exclusion_is_exact_terminal_pair_and_method_must_finish(self):
        source = (ROOT / 'Ate/Logic/SourceRecipeFidelity.swift').read_text()
        self.assertIn('itemLines.suffix(2).map({ $0.lowercased() }) == ["convert your measurements", "view full conversion table"]', source)
        self.assertIn('itemLines.removeLast(2)', source)
        self.assertIn('".!?".contains(end) else { return nil }', source)
        self.assertIn('if isSectionHeading(stripped) { continue }', source)
        self.assertIn('measuredItem(stripped) ?? unmeasuredShapedItem(stripped)', source)

    def test_failing_native_assertions_unchanged_and_every_case_required(self):
        original_sha256 = 'f0b6b369a16be02d636cfc31c447b2cdc55b6fe6906b72087161d95338bd8459'
        self.assertEqual(hashlib.sha256((ROOT / 'AteTests/SourceRecipeFidelityTests.swift').read_bytes()).hexdigest(), original_sha256)
        required = (ROOT / 'scripts/full-unit-required.txt').read_text().splitlines()
        for case in OLD_CASES + ['SourceRecipeNativeRegressionTests/' + name for name in NEW_CASES]:
            self.assertIn(case, required)
        native = (ROOT / 'AteTests/SourceRecipeNativeRegressionTests.swift').read_text()
        for name in NEW_CASES:
            self.assertIn('func ' + name + '(', native)
