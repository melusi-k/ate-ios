# Issue #38 — Today & Journal tracker hub

## Product decision

The existing **Tracker** tab is the combined daily/monthly hub. Keep the tab label **Tracker** and use **Today & Journal** as the screen heading. Do not add another tab or imply that Ate writes to Apple's Journal.

## Screen composition

1. Cooking tracker and streak, retaining month navigation, accessible date buttons, and selected-day details.
2. Apple Health insight card, including explicit Connect action and honest unavailable, entitlement-missing, denied, error, sample-data, and no-data states.
3. Health-aware meal suggestions and reflection prompts when an insight is available.
4. Local Ate journal preview, with detail navigation and the existing full searchable journal list.
5. Library/Home shortcut that switches to the Tracker tab's root.

The Tracker screen should reuse the existing Insights content in a single scroll view. Do not wrap one scroll view inside another or create a second calendar, Health model, or journal store. Keep existing routes, Shortcuts, CookingHistory, InsightsModel, and JournalStore as the sources of truth.

## Privacy and permission invariants

- Opening the app, Library, or Tracker must not request Health access.
- Health access is read-only and requested only after the user taps **Connect Apple Health**.
- Journal entries stay in Ate's local store; no claim that Ate can write directly into Apple's Journal.
- Sample data must be labelled. Missing Health entitlement, unsupported devices, denied access, and no-data states must remain distinct and explainable.
- Image-generation prompts pasted as journal text must remain ordinary text; they must not trigger image generation.

## Automated acceptance before device QA

Run focused Tracker UI tests, Health/Journal unit tests, the compile workflow, and the normal CI test targets. At minimum verify:

- Tracker tab opens with heading `Today & Journal`.
- Calendar month navigation, current-month future restriction, and selected-day empty state still work.
- The combined hub exposes the Health card, cooking calendar, and journal card without nested scrolling.
- Opening Tracker alone does not display a Health permission prompt; only the explicit Connect action can initiate access.
- Existing journal list/search/detail/edit/cancel/delete/share/Shortcuts/location/media coverage remains intact.
- Library/Home shortcut opens the Tracker root and does not disturb iOS 26 Search or the bottom accessory.

Simulator/CI acceptance is required for implementation and merge. **Physical-device and entitlement-matrix testing is deliberately deferred until the end of issue #38** and is not a blocker for implementing or merging this UI. Keep those device-only criteria open until actual evidence is recorded; do not mark issue #38 fully accepted before then.

## Device acceptance deferred to the final pass

On supported and unsupported physical devices, verify real Health authorization states, entitlement/sideload behavior, Health sample-data fallback, picker availability, local journal persistence, media/location behavior, and large-text/VoiceOver behavior. Record device model, OS, app build/channel, exact steps, result, and evidence in docs/QA_MATRIX.md and issue #38.
