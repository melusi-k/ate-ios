# Recipe sheet interaction: issue #101

10 November 2026. Scope: Library list and grid cards only. Both already present the quick-look sheet; other recipe routes keep their existing navigation. No Journal, AppStore or data-domain change.

Keep native260pt/medium/large detents. Compact-height environments use260pt/large because medium is inactive there. Use the system drag indicator and resize/scroll handoff, not custom gesture recognition or a second app navigation stack.

The detail is loaded only on first expansion so the initial glance does not eagerly build the full screen. After that, its NavigationStack stays mounted when the preview collapses. Previously switching branches destroyed the entire detail hierarchy at the compact boundary, resetting servings/editor/scroll state. The inactive surface is hidden from accessibility and hit testing. Explicit expand, expand fully, collapse and close controls provide VoiceOver alternatives to dragging. Existing Motion.anim observes Reduce Motion. No fixed latency claim is made from this source change.

Strengthen the existing test32c selection rather than add another CI lane. Preserve original list/grid/app-alive checks and add selected-title, actual detail controls, full expansion, steps scrolling, retained servings after collapse/expand, dismissal and Library/tab return checks in portrait and compact-height landscape. No timeout policy change. Named pass on the exact candidate is still required.

## Device/visual acceptance still pending

- Inspect actual compact/expanded/landscape screenshots for spacing, controls and content readability.
- On the owner's normal-text iPhone: measure card tap to usable preview and expansion to usable ingredients; report build/fullSHA and observations, not an invented snappiness threshold.
- Drag expand/collapse while scrolling, scroll handoff at top/bottom, swipe-to-dismiss, retain Library query/scroll and return after tab switching.
- Check VoiceOver focus/order and the explicit controls, Reduce Motion, portrait/landscape rotation with the sheet open, and state retention without accidental edits.
- This is a narrow prototype until reviewed; it does not accept every original #101 accessibility/performance criterion or enable Dynamic Type expansion work excluded from the current pilot.
