# Cook-plan obsolete reminder verification (#477)

Source-only hardening on the existing reminder adapter. cancel/cancelAll and
save-without-reminder already verified pending absence, but ordinary reconcile
removed obsolete IDs without checking. With denied permission or a deleted recipe,
a retained pending request could return apparent reconciliation success; the
save sheet could then say no notification would be sent without verified removal.

Reconcile now checks pending IDs after nonempty obsolete removal. A current
intent with any retained obsolete ID throws verificationFailed before adding
other desired reminders. Superseded queued work still returns without publishing
a stale verdict; later intent owns reconciliation. Existing UI catch already
keeps the saved plan and reports that reminder update failed, with retry available.
No changed UI/layout, permission loop, test timeout, activation or new CI cycle.

Two native fixtures cover denied-permission removal refusal and deleted-recipe
cleanup failure before desired adds, then successful retry retaining timer IDs.
Native XCTest/OS notifications/device delivery remain NOT RUN. Fake boundary
checks cannot prove notification-center delivery or physical-device behavior.
The earlier #477 acceptance plan remains pending, not completed by these tests.
The required-pass list adds these two native methods while preserving original25.
When folding with generation/input ownership, union all additive names rather
than overwrite either snapshot. No existing named pass may be dropped.
