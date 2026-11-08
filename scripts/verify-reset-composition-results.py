#!/usr/bin/env python3
"""Verify one complete reset-composition test-without-building invocation."""
import math
import pathlib
import re
import shlex
import sys

EXPECTED = {'ClearAllLocalDataTests': ['testJournalClearsInvalidFutureRowsAndOrphanPayloads', 'testDefaultsOwnedKeysRemovedWithoutTouchingCredentialsOrOtherApps', 'testFailureIsPartialAndOtherComponentsStillRun', 'testGateLossStopsErasureAndMissingComponentRefuses', 'testOwnedDirectoryIncludesOrphanBytesButNotSymlinkTarget', 'testJournalSaveFailureNeverClaimsComplete'], 'ClearAllResetCoordinatorTests': ['testMalformedSnapshotRowsAreUnverifiedNotFabricatedEmpty', 'testBoolOrFractionalGenerationIsRejected', 'testPutRecipeRefusesInvalidJSONPayloadBeforeSending', 'testClearReceiptMustFollowExpectedGeneration', 'testLostClearResponseIsUnverifiedNeverSuccessOrFailure', 'testResumeNeverValidatesBeforeAcquiringAndAcquireFailureStopsEverything', 'testReceiptHandoffHappensWhileControlRecordStillPresent', 'testSnapshotRejectsLegacyRepairedFields', 'testGateAcquireRaceResumesInjectedRecordSameUUID', 'testSemanticallyImpossibleRecordsFailClosed', 'testFailedRetirementIsUnverifiedAndRecordSurvives', 'testContractMissingOnResumedRecordKeepsRecordAndUnverified', 'testContractMissingFreshAttemptRetiresButFailureIsUnverified', 'testReadbackCorruptionStopsBeforeAnyResetRPC', 'testGateLostDuringCloudAwaitKeepsReceiptUnpersisted', 'testWrongTypeControlValueFailsClosedAndIssuesNoRPC', 'testCloudCommittedRecordWithoutReceiptNeverErases', 'testClearAccountRejectsOutOfRangeExpectedGenerationBeforeSending', 'testCorruptControlRecordFailsClosedAndIssuesNoRPC', 'testRelaunchAfterCloudCommitRestoresReceiptAndResumesLocally', 'testReceiptSinkFailureKeepsRecordAndNeverRetiresIt', 'testAccountSwitchMidFlightStopsAtUnverified', 'testGateLostMidLocalPhaseReportsIncompleteNeverCompleted', 'testLostClearThenResumeUsesSameRequestUUIDAndCompletes'], 'AccountGenerationPolicyTests': ['testLegacyNonemptyStateIsNeverStampedWithFreshSnapshotGeneration', 'testVerifiedEmptyFirstSyncMayAdoptGeneration', 'testRemoteResetRequiresLocalEraseEvenWhenRecipeListIsEmpty', 'testSameGenerationCanMerge', 'testOwnerChangeCannotReuseReceipt', 'testNegativeRegressedOrEmptyOwnerRefused'], 'AccountGenerationReceiptStoreTests': ['testAbsentReceiptIsOnlyNilState', 'testSaveThenFreshStoreExactReadback', 'testPresentCorruptBytesThrowInsteadOfUnknownLegacy', 'testInvalidSemanticReceiptRefusedBeforeSave', 'testSymlinkReceiptIsNotFollowed', 'testDanglingSymlinkIsNotAbsentReceipt', 'testMissingParentCannotMeanAbsentReceipt', 'testSymbolicParentCannotMeanAbsentReceipt', 'testSaveRefusesExistingCorruptOrSymlinkReceipt'], 'AccountWriterGateTests': ['testTwoInstancesShareEpochAndResetExcludesWriterEffect', 'testOldLeaseRemainsInvalidAfterResetReleases', 'testRetainedControlBlocksBetweenResetAttempts', 'testSameOwnerSessionInvalidationRejectsOldAsyncLease', 'testCorruptEpochIsNeverFreshAdmission', 'testDroppingActiveResetGateReleasesOSLockButKeepsOldEpochInvalid', 'testSynchronousNestedGraphWriterUsesSameHeldLease'], 'ResetAwareStartupTests': ['testPendingUnknownResetNeverConstructsOrdinaryGraph', 'testCompletedResetAdmitsBeforeConstructorsAndPublishesReadyAfterValidation', 'testControlAppearingBetweenResumeAndAdmissionRefusesBuild', 'testRepeatedStartCannotBuildOrResumeTwice', 'testPostFactoryLeaseFailureNeverPublishesReadyAndDoesNotClaimRollback'], 'GenerationFencedSyncTests': ['testOwnerSwitchDuringSnapshotRefusesReturnedRows', 'testSameOwnerReloginInvalidatesCapturedWriterEpoch', 'testSnapshotRejectsMixedOwnerAndDuplicateRows', 'testInvalidBatchIsRefusedBeforeAnyPut', 'testEveryPutUsesOriginalGenerationAndStopsOnPartialFailure', 'testEpochChangeAfterFirstPutStopsBeforeSecond'], 'FileResetControlPersistenceTests': ['testExactBytesSurviveFreshReaderAndRetirement', 'testMissingParentAndDanglingControlAreNotAbsent'], 'AccountResetCompositionTests': ['testActualResetPersistsReceiptRetiresControlThenPolicyAdmitsLazyGraph', 'testUnacknowledgedWatchSurfaceRetainsControlAndBlocksOrdinaryGraph', 'testPolicyRefusalPrecedesAllOrdinaryConstructors']}
SUCCESS = {'** TEST SUCCEEDED **', '** TEST EXECUTE SUCCEEDED **'}
FAILURE = {'** TEST FAILED **', '** TEST EXECUTE FAILED **'}


def validate(text):
    lines = [line.strip() for line in text.splitlines()]
    # A later success must never hide an earlier failed invocation or restart.
    if any(line in FAILURE for line in lines):
        raise ValueError('Failure sentinel in invocation log')
    if sum(line in SUCCESS for line in lines) != 1:
        raise ValueError('Expected one complete success sentinel')
    if lines.count('Command line invocation:') != 1:
        raise ValueError('Expected one command line invocation')
    command_index = lines.index('Command line invocation:') + 1
    try:
        command = shlex.split(lines[command_index])
    except (IndexError, ValueError) as error:
        raise ValueError('Malformed invocation command') from error
    required = {f'-only-testing:AteTests/{name}' for name in EXPECTED}
    selected = [arg for arg in command if arg.startswith('-only-testing:')]
    if (not command or pathlib.PurePosixPath(command[0]).name != 'xcodebuild'
            or command.count('test-without-building') != 1
            or len(selected) != len(required) or set(selected) != required
            or command.count('-resultBundlePath') != 1
            or any(arg.startswith('-skip-testing') for arg in command)):
        raise ValueError('Unexpected reset-composition invocation')
    result_index = command.index('-resultBundlePath') + 1
    if (result_index >= len(command)
            or pathlib.PurePosixPath(command[result_index]).name != 'reset-composition.xcresult'):
        raise ValueError('Unexpected result bundle')
    active = None
    pending = None
    suites = {}
    starts = set()
    methods = set()
    opened = False
    closed = False
    wrappers_started = set()
    wrappers_completed = set()
    wrappers_summarized = set()
    wrappers = {'Selected tests', 'AteTests.xctest'}
    for index, line in enumerate(lines):
        if pending and not line.startswith('Executed '):
            raise ValueError('Missing suite-owned completed summary: ' + pending)
        if 'Restarting after' in line:
            raise ValueError('Restarted invocation is not complete passing evidence')
        if line.startswith("Test Suite 'Selected tests' started at "):
            if opened or index <= command_index:
                raise ValueError('Repeated or misplaced selected invocation')
            opened = True
            wrappers_started.add('Selected tests')
        elif line.startswith("Test Suite 'Selected tests' passed at "):
            if (not opened or closed or active or pending or set(suites) != set(EXPECTED)
                    or wrappers_summarized != {'AteTests.xctest'}):
                raise ValueError('Incomplete selected invocation')
            closed = True
            wrappers_completed.add('Selected tests')
            pending = 'Selected tests'
        elif line in SUCCESS:
            if not closed or wrappers_summarized != wrappers:
                raise ValueError('Success before selected invocation completed')
        elif line.startswith('Test Suite '):
            match = re.fullmatch(r"Test Suite '([^']+)' (started|passed) at .+\.", line)
            if not match:
                raise ValueError('Malformed or non-passing suite row')
            name, status = match.groups()
            if name in EXPECTED:
                if (not opened or closed or 'AteTests.xctest' not in wrappers_started
                        or 'AteTests.xctest' in wrappers_completed):
                    raise ValueError('Suite outside selected invocation')
                if status == 'started':
                    if active or pending or name in suites:
                        raise ValueError('Nested or repeated expected suite')
                    active = name
                else:
                    if active != name or pending:
                        raise ValueError('Unmatched suite completion')
                    pending = name
                    active = None
            elif name == 'AteTests.xctest':
                if not opened or closed or active or pending:
                    raise ValueError('Misplaced wrapper suite')
                if status == 'started':
                    if name in wrappers_started or suites:
                        raise ValueError('Repeated or late wrapper start')
                    wrappers_started.add(name)
                else:
                    if (name not in wrappers_started or name in wrappers_completed
                            or set(suites) != set(EXPECTED)):
                        raise ValueError('Incomplete or repeated wrapper completion')
                    wrappers_completed.add(name)
                    pending = name
            else:
                raise ValueError('Unexpected suite: ' + name)
        elif line.startswith('Executed '):
            if not pending:
                raise ValueError('Orphan executed summary')
            if pending:
                # The summary immediately following this suite owns its duration.
                summary = re.fullmatch(
                    r'Executed (\d+) tests?, with 0 failures \(0 unexpected\) in '
                    r'([0-9]+(?:\.[0-9]+)?) \(([0-9]+(?:\.[0-9]+)?)\) seconds', line)
                expected_count = (sum(map(len, EXPECTED.values()))
                                  if pending in wrappers else len(EXPECTED[pending]))
                if not summary or int(summary[1]) != expected_count:
                    raise ValueError('Malformed suite count or summary: ' + pending)
                durations = [float(summary[2]), float(summary[3])]
                if not all(math.isfinite(value) and value > 0 for value in durations):
                    raise ValueError('Suite duration must be finite and positive: ' + pending)
                if pending in wrappers:
                    wrappers_summarized.add(pending)
                else:
                    suites[pending] = durations[0]
                pending = None
        elif line.startswith('Test Case '):
            if not opened or closed or active is None or pending:
                raise ValueError('Method outside expected suite')
            match = re.fullmatch(
                r"Test Case '-\[AteTests\.(\w+) (\w+)\]' (started|passed \(([0-9]+(?:\.[0-9]+)?) seconds\))\.", line)
            if not match:
                raise ValueError('Malformed or non-passing method row')
            cls, method, status, duration = match.groups()
            identity = (cls, method)
            if cls != active or method not in EXPECTED[active]:
                raise ValueError('Unexpected method: ' + str(identity))
            if status == 'started':
                if identity in starts:
                    raise ValueError('Duplicate method start: ' + str(identity))
                starts.add(identity)
            else:
                if identity not in starts or identity in methods:
                    raise ValueError('Duplicate or unstarted method: ' + str(identity))
                if not math.isfinite(float(duration)):
                    raise ValueError('Non-finite method duration')
                # XCTest rounds submillisecond passing methods to 0.000 seconds.
                methods.add(identity)
        elif pending:
            raise ValueError('Missing suite-owned completed summary: ' + pending)
    required_methods = {(cls, method) for cls, names in EXPECTED.items() for method in names}
    if (not closed or pending or starts != required_methods or methods != required_methods
            or wrappers_started != wrappers or wrappers_completed != wrappers
            or wrappers_summarized != wrappers):
        raise ValueError('Missing exact expected method or completed invocation')
    return suites


def main():
    try:
        suites = validate(pathlib.Path(sys.argv[1]).read_text())
    except (ValueError, OSError, IndexError) as error:
        raise SystemExit(str(error)) from error
    for name, duration in suites.items():
        print(f'Verified {len(EXPECTED[name])} exact named passes for {name}; suite {duration}s')


if __name__ == '__main__':
    main()
