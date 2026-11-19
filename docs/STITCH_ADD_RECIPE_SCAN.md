# Add Recipe scan-review presentation, screen 2

Part of #613. Source slice only, not issue closure or native acceptance.

## Implemented boundary

The independent `AddRecipeScanFeature.stitchAddRecipeScanEnabled` flag defaults ON. The new presentation keeps the original Add a recipe heading, Link/Image/Prompt picker, fields, single-image selection/camera replacement, generation, source badge, quality warnings, repair/confirmation, editing, save and discard actions. It adds a draft-review card using the current editable recipe's title, ingredient entry count, step count, positive draft servings and positive total time. Missing/invalid time and servings stay explicit. Counts are entries in the draft, not extraction completeness or accuracy. Legacy decoded servings may default to 2; the card labels them draft servings, not verified source yield.

The new display never shows the model's confidence percentage or a mock 94% OCR accuracy. Low-confidence quality checks still run and still block saving under their original rules. Their ON explanation uses plain uncertainty. Source badges continue to distinguish page import, guessed photo, Demo and other existing provenance. No source identification, ingredient, quantity, unit, method, time, generation, repair, persistence or cancellation algorithm is replaced by this presentation.

The image-ready message explains that the current single image can be replaced before reading. The existing picker/camera actions replace the input. It does not claim a new post-parse retake or append-page operation. The original photo editing/cover flow remains separate from source text.

## Deferred, not simulated

Scan Another Page, multi-page capture, page merge/order/edit rules and any page-count UI are deferred. There is no hidden page concatenation or inactive button suggesting a working scanner. No mock OCR confidence, nutrition/kcal, background permission, paid service or production backend change is added. This is not the full Stitch screen acceptance.

## OFF and rollback

An explicit Boolean `StitchAddRecipeScanEnabled = false` in the built Info.plist uses the old Add/review display. No remote toggle or project build-setting substitution is claimed. In UI-test mode only, `-qaStitchAddRecipeScanOff` provides OFF. Production ignores the QA argument without UI-test mode. The flag is independent of #612 and every other screen. Revert is also safe because no schema, stored draft format or migration changes.

## Source and automated checks

All source from coverEditor through the end of AddRecipeSheet is byte-pinned to the #610 parent, covering cover/input data handling, OCR request preparation, generation ownership, source binding, repair, restore/retry and diagnostics. Save, discard and quality checks retain their original operations. CameraPicker, RecipeEditor, RecipeCardView, Models and backend files are unchanged.

Three new native unit sources check summary values without mutation, unknown/invalid values, changed draft values, entry counts and independent ON/OFF flag behavior. Their three names join the existing full-unit required-pass union, replacing none.

Five new native UI sources cover ON draft counts and original edit/save, OFF original review, real JSON-LD fixture identity/source badge, normal-text landscape failure/retry/discard and one-image replacement/read. The image case uses the existing screenshot fixture and actual Vision OCR in the mock test backend. These are UI wiring tests, not real-model or extraction accuracy evidence. Existing quality-repair, interrupted-generation and source-regression tests remain untouched.

All five new UI methods are selected and individually named-pass checked in the existing presentation-creation Transient generation Retry recovery step. Existing xcresult screenshot export includes their captures. No new job, dispatch, retry, timeout, test allowance or gate waiver is added. The existing 180/240-second test allowances and 110-minute job cap remain.

## Native acceptance still outstanding

Native build, full units, mandatory Journal regressions, Add UI execution, pixels and physical-device acceptance are UNRUN here. Source/Python checks do not qualify Swift. Reviewer owns publication and the existing native route. No HTML screenshot substitutes for native evidence.

Within that route on iPhone 18 Pro at normal text:

- Inspect empty Link/Image/Prompt input, image-ready, loading, source-bound imported review, uncertain generated draft, editing, repair, disabled/enabled save and OFF fallback. Preserve actual screenshots as soon as available.
- Inspect portrait and landscape with keyboard both present and absent. Title/Cancel/source picker/summary/editor/save must be readable and reachable without clipping or overlay collisions. The native Add sheet/detents and underlying tab, floating Search and timers must keep their original behavior. The summary uses ViewThatFits for metadata and scrolls with the original content. Source code does not prove those pixels.
- Replace an image before reading, cancel camera/photo selection, use a source screenshot and unreadable image, repair a draft, edit ingredients/units/method/time, and compare against the original. Never label a guessed food photo as a source-bound scan. Never claim an entry count proves all source ingredients were captured.
- Cancel/Keep editing, Cancel/Discard, double Save, delayed picker completion, interrupted generation, relaunch/retry and source-bound dish confirmation must keep their existing ownership and no-duplicate contracts. The unchanged code still requires native regression evidence.
- Offline/model-unavailable/transient failures must retain input and draft and offer the original explicit recovery. A failure must not fabricate a new dish or claim the source was read. Existing private-mode, permission-denied and camera-unavailable behavior remains. A system camera success is not extraction success.
- VoiceOver must read source provenance, title, draft counts/servings/time and uncertainty, then the original editor/repair/save/Cancel actions in a useful order. Confirm unique action identifiers, disabled save state and no accuracy percentage in ON. Metadata labels in code are not a VoiceOver pass.
- With Reduce Motion ON, repeat generation/error/retry and review. Existing Motion policy remains unchanged; no new animation is introduced. Larger text is supplementary to normal-text acceptance, not substituted for it.

Open visual/accessibility or native regressions block acceptance. Do not infer them green from the final-head Python count.
