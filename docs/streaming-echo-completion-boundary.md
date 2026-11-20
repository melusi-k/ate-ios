# Echo rejection test: await session settlement

20 November 2026. Branch-only descendant of PR63715309387c4a1d66a93c9f6ee4cc97454e608ee58. Native final-head UNRUN. No production behavior or timeout change.

## Evidence and cause boundary

Parent supplied run44715543772 artifact14626091276 full-unit-tests-c5b854ff.log. Independently read lines3011–3014: RecipeStreamingTests.testRejectedExampleEchoPreviewNeverBecomesSavable fails in0.043s. Line231 sees the complete Mogodu partial preview with beef tripe, onions, garlic, curry powder and beef stock; line234 sees no error message. Empty suggestions/savedIDs assertions do not fail. The console does not contain per-phase timestamps proving the exact scheduler interleaving.

Source pins an incorrect test-completion boundary. The injected streamSuggestion calls returned.fulfill() before return echo. The real backend still has to resume from createSuggestion, check cancellation, run isExampleEcho and throw. RecipeDiscoverySession then catches that error to set message; its defer clears preview/loading and cancels its deadline. Waiting for the inner backend expectation therefore cannot establish those outer session effects have happened.

The fixture meets the unchanged echo guard: it has beef tripe plus four other signature matches, and the actual generation context contains Vegetable Soup/carrot, not tripe/Mogodu/ulusu. There is no source-supported exemption bypass here. Native failure values are consistent with the premature completion boundary, not proof that the echo became savable. Final-head native testing is still needed to verify the correction and expose any real rejection defect.

## Change

Keep every original preview, empty suggestions, empty savedIDs and message assertion. After releasing the gate and observing the injected backend return, create a bounded main-actor observer that yields until session.loading becomes false. Use the existing2s fixture wait limit, then cancel the observer. Session loading=false is set in the real catch/defer completion path. Assert it is false and assert the exact expected echo-rejection message in addition to the original NotNil.

This waits for the state the test asserts, not an arbitrary sleep, retry or larger allowance. It does not skip checks while loading. If settlement never arrives, the2s wait fails; if the echo is admitted, the original empty-suggestions check and exact-message assertion fail; if deadline/error differs, exact-message fails. Production60s timeout, token isolation, backend/session code, required-test selectors and workflows are unchanged.

An exact additive inverse runs before historical source guards. Historical hashes are not replaced. New static guards check reconstruction, mutated fragments, ordering and observer cancellation. These are not Swift compilation, scheduling proof or native evidence.

Reviewer next: retain the original failure log, run this exact method on the final head and require all original and strengthened assertions, then run blocking native units plus compile/Journal on that exact candidate. No automatic retries, timeout raises, suppressed failures or pass-marker override. No popup or paused UI work included. No remote publication, dispatch/rerun, merge or build cut is performed by this packet.
