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
    'testQuietConnectAndSampleMarksSurviveLandscapeRotation',
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

# test-without-building reports TEST EXECUTE SUCCEEDED on current Xcode.
# Keep a single completed success marker and reject any failed invocation.
lines = [line.strip() for line in text.splitlines()]
success = {'** TEST SUCCEEDED **', '** TEST EXECUTE SUCCEEDED **'}
failure = {'** TEST FAILED **', '** TEST EXECUTE FAILED **'}
if any(line in failure for line in lines) or sum(line in success for line in lines) != 1:
    raise SystemExit('Expected one success marker and no failure marker')
verify('InsightsPresentationUITests', EXPECTED)
verify('InsightsPresentationTests', UNIT_EXPECTED)
