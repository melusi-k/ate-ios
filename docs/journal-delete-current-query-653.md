# Current detail disappearance query

Base: hosted #653 8a05abf1f21d1e43a1eacf4892ad9cef2d078637.

One-line rationale: observe the current detail identity after edit/reopen/delete instead of retaining the pre-edit element handle, with the same strict disappearance assertion and10s budget.

First-run Journal job136956530675 failed the existing detail-gone assertion at source356, then exceeded its240s allowance during later cleanup. Post-delete pixels show Journal root and the deletion toast. Current confirm99.38s to screenshot101.17s matches earlier green84.59s to86.26s; the earlier green detail-gone query completed in0.42s, current query took9.259s before its failed expectation. A later19:51:43Z sample has app main idle, runner cleanup/screen-recording waits, not a product delete loop. It does not sample the earlier failed query. Stale observation versus AX transport remains uncertain.

Only the confirmed-delete boundary re-resolves any("journal.detail.text"). The waitUntilGone implementation,10s timeout, confirmed-delete action, delete-error assertion, root return and history-row absence check stay byte-identical. No screenshot pass fallback, retry, new wait or product change. Existing red remains red. This is an observation-correctness candidate, not a proved repair or persistent-deletion acceptance.

Exact inverse restores the entire prior UI-test file hash. Historical Today-tab fixture and hashes remain unchanged; the new inverse is normalized first. Python source checks are not native execution. Fresh ordinary exact-head native qualification and independent review are required; builder does not merge.

Source: https://github.com/melusi-k/ate-ios/actions/runs/44940522232/job/136956530675
