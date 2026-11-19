# Cook Mode readability, screen 4 source slice

Part of #615, not closure or native acceptance.

## Presentation boundary

`CookModeFeature.stitchCookModeEnabled` defaults ON. ON puts the existing Cook body in a scroll host, adds an honest Cook Mode/recipe title heading and keeps full-size wrapped step instructions instead of shrinking them to 50%. The same instruction, temperature conversion and step accessibility identity are retained. Existing progress, other running-step timers, active timer display/controls, ingredient sheet and explicit voice control remain inside this scroll content. Back/Next/Finish stay in the existing real bottom safeAreaInset outside the scroll host, with the existing measured footer/timer reserve unchanged.

OFF keeps the original non-scroll layout and scale factor. Built Info.plist Boolean StitchCookModeEnabled=false disables the presentation. Only UI-test mode accepts -qaStitchCookModeOff. No remote toggle or new project setting substitution is claimed. The flag is independent of other screen flags and owns no session, timer, microphone or completion state.

The new scroll modifier has no action, task, timer, session write or lifecycle hook. Shared current-step ownership, start/pause/reset/parallel timers, exit cleanup, running timer behavior, Live Activity, explicit Finish, completion-outbox failure/retry, history, reflection handoff and voice methods are unchanged. No automatic finish or pause/start/reset is introduced. A timed step still waits for an explicit supported timer action.

## Voice and rescue limits

No new voice feature is added. The existing microphone action is opt-in and reports its real controller state. OFF/ON keep the same controller, permission handling, stop/error paths and parsed command behavior. There is no always-listening wake word, rescue conversation, safety advice, fake audio, auto-paused timer, success certification or Skillet Rescued control. All proposed rescue/wake-word acceptance remains deferred under its own future scope. UI-test voice simulation is not physical-device microphone evidence.

No nutrition/kcal, pantry, calendar, recipe rewriting, permission, paid service or production backend change. A Cook completion remains a cooking record, never an automatically logged consumed meal.

## Evidence and remaining checks

Two unit sources cover independent default ON, built OFF and UITesting-only QA OFF, including unrelated screen arguments not changing this flag. Two required names join the existing strict full-unit union, replacing none. Three UI sources cover ON scrolling/title, explicit timer start, running timer exit/reentry and final Finish readiness; OFF original layout; normal-text landscape instruction/footer clearance and Back/Next. They reuse the unchanged saved-sheet fixture and existing real navigation. They do not automatically Finish the cook or claim physical timer/voice accuracy.

The new UI class is selected and per-method named-pass checked in the existing presentation-creation transient-generation-retry step; its existing xcresult export retains screenshots. Existing account-cooking timer, shared-step, Finish-accessory and Journal/reflection gates stay unchanged. No new job, dispatch, timeout, test allowance, retry or gate waiver. Existing 180/240-second test allowances and 110-minute cap stay.

Exact inverse reconstructs base CookModeView and workflow bytes before historical hashes and mutation guards. Python/source checks are not Swift compilation or native acceptance. Native build, full units, mandatory Journal, all UI execution, actual pixels and physical-device acceptance are UNRUN here. Reviewer owns publication and native evidence.

Within the existing qualification path on iPhone 18 Pro at normal text:

- Inspect ON/OFF portrait and landscape, short and long full instructions, source temperature conversion, progress, parallel timer links, timer value/buttons and pinned actions. Scroll to the final sentence and timer controls, proving they clear Back/Next/Finish and any retained resume/timer accessory. Keep actual screenshots immediately. No HTML pixel substitute.
- Start a timer explicitly, move to another step, leave/reopen, rotate, resume via session/timer/deep link and confirm running timers continue with their original state and shared current step. No timer starts or pauses simply from entering, scrolling, rotating or changing a feature flag. Test running/paused/reset/completed timer cases with existing chime/haptic/Live Activity evidence.
- Verify the original Ingredients sheet scaling/checklist/session behavior and all existing shared-step/deep-link actions. Missing/deleted recipe and empty steps keep Nothing to cook here and safe exit. Offline must not lose the session or fabricate content.
- Explicit Finish must be reachable once, record the same completion path, preserve outbox failure/retry, leave only through the existing owner and offer reflection without duplicate history or auto-consumption. A screenshot showing Finish is not a completed-cook pass. Existing mandatory Journal and Finish regressions are still required.
- VoiceOver must read full current instruction/position, timer value and actual timer control state, accessible Ingredients/Exit/voice action and Back/Next/Finish without hidden duplicate actions. Test permission-denied/unavailable and explicit Stop on a physical device for voice; no simulator simulation qualifies microphone behavior.
- Reduce Motion must retain navigation/scroll/progress/timer behavior; no new animation is added. Larger text is supplementary, not a replacement for current normal-text acceptance. Do not shrink long instructions to make a screenshot pass.

Any clipping, inaccessible pinned action, stopped timer, stale shared step or native regression is a blocker to fix and inspect again, not a pass inferred from source tests.
