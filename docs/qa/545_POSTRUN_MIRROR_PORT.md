# Exact #545 screenshot mirror port

Base e0d2b70f67e74965545fd434f9458db2968a2b22, run43766520050/job132972780926. Ports the existing #539 screenshot transport change (hosted184b499) only; no application code or test assertions, waits, screenshot calls, attachments, or execution budgets change.

Retry tap105.73s, synthesis106.15s. Screenshot captured/attached108.12s (manifest01:40:22.103UTC) shows Journal root, No journal entries yet, and Journal entry deleted toast. This is BEFORE the first waitUntilGone query129.19s. It disproves slow deletion as the cause of the line394 failure. Live PNG base64 printing occupies the earlier gap; exact blocking stack is unproven because no spindump exists.

Host unified evidence01:40:43.176 receives AX query, main responds, but traversal continues through the already-empty Journal: No journal entries yet52.433, computed type56.000, further attributes59.745. This exceeds the10s waiter and supports AX query overrun. Removing live stdout overhead is justified, but NOT proven to cure that AX cost. The original red remains a real assertion and cannot be waived as a pure stall.

Native proof required: exact patched-head Journal open-state lane, unchanged testConfirmedDeleteFailureKeepsDetailAndExplicitRetryRemovesEntry, with failure-retained-detail and successful explicit-retry pixels, successful original gone/detail/history assertions, and byte-verified exported raw screenshot/mirror log. The ordinary confirmed-delete journey must also pass. Source validation is not native acceptance. Native/typecheck/patched pixels UNRUN.

Separate #543 Nutrition head91413ebf: failed-save journey spends~149s reaching Food diary because AX frame reads take5-16s. Both save errors, retained name, cancellation and visible empty state pass before terminate229.27s; relaunch230.32s/idle238.51s reaches240s cap before post-relaunch assertions. No save-state defect shown; persistence after relaunch remains unverified. No Nutrition patch or budget increase.

Source PRs close only after reviewer confirms destination commit; branches kept.

Port-specific test adaptation: #545 lacks the independent #539 QA8 guard test module. Do not import it into this slice. The mirror tests retain their full-file inverse SHA guard and assertion-mutant rejection; removed only the redundant invocation of that absent module.
