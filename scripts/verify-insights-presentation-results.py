#!/usr/bin/env python3
"""Fail closed unless the bounded Insights class records every expected nonzero pass."""
import pathlib
import re
import sys

EXPECTED = {
    'testSampleScenarioMarksEveryHealthDerivedSurface',
    'testUndecidedHealthIsCompactOptionalSetupAndStillConnects',
    'testDeniedHealthIsQuietNoticeWithoutConnect',
    'testUnavailableAndMissingEntitlementAreQuietNoticesWithoutConnect',
    'testConnectedButEmptyHealthKeepsQuietNoDataNotice',
    'testConnectedHealthStateOffersNextMealIdeaAction',
    'testCookingHistoryInsightLinksGeneratingRecipe',
    'testFoodJournalTileRoutesToUnifiedTimeline',
    'testJournalTileNeverPresentsForcedBadOpenAsHealthyEmpty',
    'testQuietConnectAndSampleMarksAtMaximumAccessibilitySizeAndLandscape',
}
UNIT_EXPECTED = {
    'testNotDeterminedOffersSingleQuietConnect',
    'testDeniedIsQuietNoticeWithoutConnect',
    'testUnavailableAndMissingEntitlementNeverOfferConnect',
    'testRequestedIsTheOnlyConnectedPresentation',
    'testEveryHealthDerivedTileRequiresSampleBadgeWhenSampling',
    'testNoSampleBadgeWithoutSampleData',
    'testNonHealthTilesNeverCarrySampleBadge',
    'testLibraryTodayCardIsMarkedWhenSampling',
    'testWeeklyCookingCandidateLinksItsRecipes',
    'testFirstTimeCandidateLinksNewRecipes',
    'testCookingRhythmFallbackLinksMostCookedRecipe',
    'testRelatedRecipesNeverChangeEvidenceFingerprints',
    'testMakeCapturesWeekAndFirstTimeReferences',
    'testRecipeReferencesSortMostCookedFirstThenTitle',
    'testRecipeReferencesTieBreakIdenticalTitlesOnID',
    'testRecipeReferencesNegativeLimitReturnsEmpty',
    'testRecipeReferencesDropUnknownIDsAndRespectLimit',
}
text = pathlib.Path(sys.argv[1]).read_text()

def verify(class_name, expected):
    pattern = r"Test Case '-\[\S*" + class_name + r" (\w+)\]' (passed|failed) \(([0-9.]+) seconds\)"
    rows = re.findall(pattern, text)
    names = [row[0] for row in rows]
    if (set(names) != expected or len(names) != len(expected)
            or any(status != 'passed' or float(seconds) <= 0 for _, status, seconds in rows)):
        raise SystemExit(f'Expected exact {len(expected)} nonzero {class_name} passes, found {rows!r}')
    print(f'Verified {len(expected)} named nonzero {class_name} passes')

if '** TEST SUCCEEDED **' not in text:
    raise SystemExit('Missing TEST SUCCEEDED')
verify('InsightsPresentationUITests', EXPECTED)
verify('InsightsPresentationTests', UNIT_EXPECTED)
