# Cook Mode: step navigation and explicit finish

Status: Draft

Implementation state: Implemented in the cited source; runtime acceptance needs separate evidence.
Reviewed source: main `201651769c6919bceb71b257a25567cf41c45cfa`, 12 November 2026.
Source owner/reviewer: not yet assigned for this pattern record.
Scope: `Ate/Views/CookModeView.swift` (`CookModeView`), `Ate/Logic/CookCompletion.swift`, `Ate/Views/CookReflectionOfferSheet.swift`, and the hosting route's callbacks. This is a source-backed record, not a new interaction proposal or device pass.

## Entry and step states

The host supplies `recipeID`, a completion outbox and optional exit/completion/reflection callbacks. Missing recipes or empty steps show `RecipeNotFoundView` with "Nothing to cook here" and an exit action. On appearance, resume uses `CookSessionRecovery.resumeStep`: saved session step or running timer step, bounded to current recipe steps. Opening Cook Mode updates session progress; it is not evidence of a finished cook or eaten food.

The bottom safe-area controls expose Back (disabled at the first step), Next step (`cookNextStep`) before the last step, and Finish cooking (`cookFinish`) on the last step. Step changes update the cook session while `CookFinishState` permits writes. The view hides navigation/tab bars. Voice/timer details are not fully audited by this record.

## Finish, persistence and failure

Only explicit Finish calls `finish(_:)`. The source order is: prepare/read back live session identity, enqueue a stable `cook-<sessionID>` event, record completed-cook history, clear that same completed session, then call `complete(_:)`. The stored event preserves its identity/date on a retry. Separate stores are not one transaction: this is at-least-once behaviour, not exactly-once or an fsync guarantee. Finishing cooking does not itself log an eaten meal or Health sample.

Failure keeps a visible "Could not save this cook" alert. Text distinguishes unreadable outbox, unreadable history and other partial-save failures. "Try again" dismisses the alert; the user can explicitly Finish again while the session remains available. An unreadable outbox additionally offers "Set aside and continue". Do not describe a failed attempt as rolled back or completely saved.

## Optional reflection and exit

`complete(_:)` uses `CookFinishState.begin()` to guard completion, reports `onCompleted`, and presents the reflection offer. Its dismissal owns the exit sequence: leave Cook Mode once, then call `onReflect` only when the user chose to write. Done or swipe dismissal does not request a note. The host must wait for its own dismissal before routing a chosen note. The callback comment describes opt-in hosting, but `CookReflectionOfferSheet` always renders "Add a note"; `showReflectionNudge` gates only the nudge text, not that action. A missing callback is therefore a source-contract gap to verify, not a guaranteed hidden option.

On disappearance the view restores the idle timer and stops voice. Exit cleans up idle recipe timers and delegates to `onExit` or pops its path. Leaving without explicit Finish is not a cook-completion event.

## Verification boundary

The source contains explicit control identifiers and minimum Back hit height, but this record supplies no new rendered layout, VoiceOver, contrast or physical-device verification. Hosted/pushed navigation, timer/voice cancellation and host presentation ordering need their own exact-head evidence. Existing test definitions or historical passes are not re-certified here. Figma mirroring and full #366 journey acceptance remain open.
