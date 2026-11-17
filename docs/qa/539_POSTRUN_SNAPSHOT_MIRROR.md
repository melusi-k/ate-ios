# #539: move screenshot mirrors outside the XCTest execution budget

## Observed failure

Exact source `066d5787ca1380be31885a072acc1d5ce8cd6562`, Journal job132970031054, run43765629378, artifact14184241817:
https://github.com/melusi-k/ate-ios/actions/runs/43765629378/artifacts/14184241817

`testManualReflectionEditSaveCancelAndConfirmedDelete` remains FAILED. Confirm tap occurs150.14s, retained screenshot157.26s, four-minute allowance expires while printing its base64 mirror, mirror output finally ends before297.87s, detail absence query starts320.63s, waiter reports TimedOut. The message "Still presented" is an unconditional waiter failure description, not a positive observation that `exists` returned true.

The actual post-confirm screenshot shows the Journal root, "Journal entry deleted" toast and "No journal entries yet". No detail or confirmation is visibly presented. At22:19:20-25UTC, all250 runner samples are inside test line349 -> shot line103 -> print -> __write_nocancel/VNOP_WRITE. The app process26229 has250/250 idle main-thread mach_msg samples and0.004s CPU. Later the unified log's exact `journal.detail.text` query returns null with `XCTPerformOnMainRunLoop work timed out after60.0s`; subsequent FirstMatch messages explicitly say no match found. This supports a runner screenshot-output stall followed by AX query failure, not a retained visible detail or proven hidden stale AX node. It does not prove every later delay has the same cause.

The alert host and deleteConfirmedEntry body are byte-identical main4aa5 to hosted#539. No app delete patch is justified by this failure.

## Cross-run scope

| Candidate | Boundary | Snapshot-output cause? |
| --- | --- | --- |
| #539066d5787, job132970031054 | Confirmed delete completed; runner sampled in SNAPSHOT-CHUNK print | Directly established for sampled overrun |
| #532aafed988, job132919057685 | Cook-exit title AX retries consume~130s before late journey and180s cap | No live base64 in AteUITests.shot; failing log has no SNAPSHOT markers. Same journey #534 passed34.897s. Not the direct print path. |
| #5377e8ffb6e, job132920768632 | Candidate-card setup app.launch timeout before test body; later CoreSimulator unavailable | Before screenshot execution, not the direct print path. |
| #540e64b9408, job132929292125/run43752463839 | Parent's corrected diagnosis: pre-test runner handleStalledWait crash at204.69s | Parent explicitly corrected earlier "setUp" shorthand; not a screenshot-print path. Raw #540 terminal log not independently re-read in this packet. |

No shared underlying host-pressure root cause is asserted. This change is not a fix for launch, pre-test or unrelated AX stalls. No rerun or historical outcome is changed by this analysis.

## Same-pixels gate

Before removing live printing, compared the exact exported raw PNG `DE065E32-553F-447C-9DC1-5D591B5C92C8.png` with PNG bytes decoded from the original SNAPSHOT chunks. They are byte-identical:376008bytes, CRC3665447175, SHA256`446ceacfd36bdaebfec9c2f40e94f83dc532fc45f112cbef5edf3d1a746ee900`. Both images were visually inspected. The manifest also lists the readable exported copy with the same byte length/CRC. The new post-run script round-tripped that real PNG to mirror text and back, yielding the same SHA. No screenshot is resized, recompressed or recaptured.

## Change

- All original `shot` calls remain at their exact journey points. `XCUIScreen.main.screenshot`, named `XCTAttachment`, `.keepAlways`, and `add(attachment)` are unchanged.
- Only base64 encoding and print-loop work move out of `JournalOpenStateUITests.shot`.
- Existing always-run export keeps raw PNGs and manifest. A new always-run step after export writes exact PNG base64 mirrors into retained `journal-snapshot-mirror.log`, not the runner console or an in-flight XCTest log.
- The mirror adds originating test/exported filename/byte-count/SHA metadata. It rejects missing manifest, missing PNGs, an empty Journal PNG export and paths escaping the export directory. A missing mirror is an explicit diagnostics-step error, never fake evidence.
- Original raw attachments, readable copies and xcresult remain in the artifact. Consumers previously parsing SNAPSHOT chunks from `journal-open-state-ui.log` must now read `journal-snapshot-mirror.log` for this class. Other suites are untouched.
- No test assertion, selection, wait, screenshot count, teardown, retry or timeout changes. Native240/480-second allowances remain unchanged. App source is untouched.
- Existing frozen source hashes are preserved. A strict inverse reconstructs the exact original screenshot helper before the existing guard chain. The original frozen guard still rejects a changed delete assertion. An additional exact workflow inverse proves the only workflow changes are the post-run step and retained log path.

## Validation and remaining qualification

309Python tests PASS in working and fresh depth-1 checkout; Swift grammar PASS; workflow shell syntax PASS; diff-check PASS; real PNG mirror roundtrip PASS. Python, grammar, YAML/shell and retained-pixel checks are not an Apple compiler or native test execution. Native build/typecheck, exact-head UI run, timing improvement, screenshot-export execution on the patched workflow and device acceptance are UNRUN.

Reviewer must run the unchanged Journal journey on the exact candidate and inspect original named attachments plus the post-run mirror hash metadata. Keep the historic red and #539 merge hold intact until the owner makes the required decision. No app correctness pass or generalized runner-stall cure is implied.
