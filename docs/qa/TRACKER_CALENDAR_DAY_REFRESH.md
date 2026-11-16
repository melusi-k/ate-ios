# Tracker calendar-day refresh

Base: main 4aa5e5ed62c84cba4bb9a9008ae35810956d91ae.

## Evidence

#543 head91413ebf, Account run43765858664/job132970705845: testSelectingTodayShowsDayDetailsAndExplicitEmptyState started2026-11-15 23:59:43.723 UTC. Tracker opened before midnight; test selected day16 after midnight and failed the today-label assertion at17.81s. Reviewer decoded AX shows day15 still has today, day16 does not; pixels show the prior outline15 and subsequent Monday Nov16 empty-day sheet. Exact device IANA timezone was not captured. Source view and test unchanged main to#543. Earlier#532,#534,#523,#535 passes all selected15 before midnight. This is independent of the photo source slice.

## Change

The grid owns an ephemeral, non-persisted calendar snapshot used by both the today marker/label and current-month navigation boundary. Calendar-day-change notification, active scene and appear refresh that snapshot. No timer, retry, extra wait or test date override. Follow month/year rollover only if browsing the previously current month; retain older history browsing. Existing timezone/locale reset behavior is preserved, now with a refreshed snapshot. No cooking event date, selection semantics, storage or journal mutation changes.

Foundation-only state has four native tests for day rollover, foreground catch-up across month/year, retaining older browsing, repeated/backward refresh. Source contract checks the event wiring uses the same snapshot and freezes the original entire CookingTrackerEntryUITests file. Test76 is untouched.

## Verification

Python source suite and Swift grammar validation recorded in delivery logs. Native Swift typecheck/build/unit/UI tests UNRUN here. No patched simulator pixels available: source-only slice pending Reviewer native run and visual confirmation of marker/label rollover. Original evidence pixels inspected; this does not constitute patched UI acceptance. Calendar notification delivery still depends on the OS; active/appear catches up after suspension.

No remote publish/merge performed. Source PRs close only after the reviewer confirms the destination commit; branches kept.
