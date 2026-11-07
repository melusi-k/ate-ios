# Issue #38 — Insights hub

## Product decision

Current navigation decision (2026-11-05): the tab is **Journal** with the book.closed symbol and Journal root. **Insights & Cooking History** is a pushed destination inside Journal. This supersedes the former Insights tab/root naming below; historical acceptance evidence is not fresh qualification of the renamed tab. The screen continues to contain cooking history, read-only Health insights, and the local Ate journal. Do not add another tab or imply that Ate writes to Apple's Journal. This is a cross-issue UI change: cooking completion, persistence, streak/calendar semantics, and early-exit behavior remain owned by [issue #31](https://github.com/melusi-k/ate-ios/issues/31); Health and journal acceptance remains owned by [issue #38](https://github.com/melusi-k/ate-ios/issues/38).

## Screen composition

1. Cooking tracker and streak, retaining month navigation, accessible date buttons, and selected-day details.
2. Apple Health insight card, including explicit Connect action and honest unavailable, entitlement-missing, denied, error, sample-data, and no-data states.
3. Health-aware meal suggestions and reflection prompts when an insight is available.
4. Local Ate journal preview, with detail navigation and the existing full searchable journal list.
5. Library/Home shortcut that opens Insights & Cooking History above the Journal root.

The Insights screen should reuse its existing content in a single scroll view. Do not wrap one scroll view inside another or create a second calendar, Health model, or journal store. Keep existing routes, Shortcuts, CookingHistory, InsightsModel, and JournalStore as the sources of truth.

## Privacy and permission invariants

- Opening the app, Library, or Insights must not request Health access.
- Health access is read-only and requested only after the user taps **Connect Apple Health**.
- Journal entries stay in Ate's local store; no claim that Ate can write directly into Apple's Journal.
- Sample data must be labelled. Missing Health entitlement, unsupported devices, denied access, and no-data states must remain distinct and explainable.
- Image-generation prompts pasted as journal text must remain ordinary text; they must not trigger image generation.

## Automated acceptance before device QA

Run the full `CookingTrackerEntryUITests` target, the Cook Mode completion/early-exit integration tests, Health/Journal unit tests, the compile workflow, and normal CI test targets. PR #59 wires the Tracker target and Cook Mode integration tests into the main-push release gate; new #38 hub tests must remain in that same target. At minimum verify:

- Journal tab opens with the native navigation heading `Journal`; its named route opens `Insights & Cooking History`.
- Calendar month navigation, current-month future restriction, and selected-day empty state still work.
- The combined hub exposes the Health card, cooking calendar, and journal card without nested scrolling.
- Opening Insights alone does not display a Health permission prompt; only the explicit Connect action can initiate access.
- Existing journal list/search/detail/edit/cancel/delete/share/Shortcuts/location/media coverage remains intact.
- Library/Home shortcut opens Insights & Cooking History above Journal and does not disturb iOS 26 Search or the bottom accessory.

Simulator/CI acceptance is required for implementation and merge. **Physical-device and entitlement-matrix testing is deliberately deferred until the end of issue #38** and is not a blocker for implementing or merging this UI. Keep those device-only criteria open until actual evidence is recorded; do not mark issue #38 fully accepted before then.

## Device acceptance deferred to the final pass

On supported and unsupported physical devices, verify real Health authorization states, entitlement/sideload behavior, Health sample-data fallback, picker availability, local journal persistence, media/location behavior, and large-text/VoiceOver behavior. Record device model, OS, app build/channel, exact steps, result, and evidence in docs/QA_MATRIX.md and issue #38.
