# Cook completion journey correction, ingredient timeout unclassified

Exact base #522 41badff3. Evidence run 43345849573, artifact 14009565393.

Completion always presents CookReflectionOfferSheet with saved-history confirmation
and Done/Add a note. Its onDismiss exits Cook Mode. The failing test never tapped
Done: after Finish it found a background "Cook mode" button, then globally queried
an absent TabBar at 44.42/75.44/106.50 seconds and timed out evaluating snapshots.
This is a concrete journey mismatch. It does not establish busy main-thread work,
a looping animation or the duplicate alert-ID cause found separately on #527.

The corrected test requires cookCompletion.recorded, exactly one cookReflection.notNow
button, taps Done and then follows the existing strict recipe-detail navigation back
to Journal. All original cooked-day/current-date/history/nonempty recipe assertions
remain. No waits/timeouts or product runtime code changed. The sibling explicit Exit
journey already uses this strict route and passed in the supplied log.

Ingredient bounded read: the supplied log reaches the final normal-imperial screenshot
at 106.31 seconds and Tear Down at 106.33 after label, gathered value, hit-target and
visible-frame checks. The execution allowance is reported afterward. It does not
identify a failed value assertion, duplicate-ID error, busy main thread or animation
stack. Cook sheet code has no repeating animation/timer task. This does not prove
runtime teardown is healthy; its cause remains UNCLASSIFIED. No speculative cleanup,
UI-test timeout increase, test removal or fabricated product fix is included.

Settings sync is separate: runner crashed at XCTWaiter handleStalledWait while
preparing tests, before an ordinary case execution trace. It remains quarantined,
not a pass and not evidence of a shared product cause.

191 Python checks PASS, diff check PASS. Native UI test/build/pixels UNRUN. The exact
completion method must be rerun on this corrected head; ingredient timeout remains
an independent unresolved qualification failure. Rollback is this journey correction
only. No remote merge/publication, storage or workflow gate changes.
