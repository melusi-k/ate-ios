# #515 scoped rewrite vs explicit quality repair

Incremental on photo-scoped #513b2c6f8f (OCR-servings/step-fixed #5095b35d4d beneath it) / quality stack. No publishing/native/model pass.

Source finding: saved RecipeDetail's old Improve with AI button overwrites ask
with improvePrompt then invokes rewrite, whereas the adjacent typed Ask ate action
uses ask. Those are now explicitly separate: Repair these gaps sends repairQuality
true without changing typed ask, and the typed request remains a scoped rewrite.
Saved-card apply rechecks original snapshot equality to refuse stale results.

Bounded exact Make this vegan variants can be detected as a no-op only for an
explicit known plant-ingredient list with no animal cue in steps/notes. The UI
states no changes and reminds about packaged ingredients, without writing the
card. Backend independently returns identical original BEFORE model/fallback.
This covers the supplied simple chakalaka shape; unknown ingredients (stock,
compound sauces etc.) are not declared vegan by heuristic.

A non-no-op simple vegan candidate must retain title/description/servings/total,
ingredient quantities/units/notes, step count/order/times and all instruction text
except whitelisted ingredient-name substitutions. Partial animal substitution,
new salt/drain note, 180C/other unsolicited rewrite rejects without updating. Only
known plant names and specific substitutes are admitted; broader vegan technique
changes may refuse and require a manual/specific edit. No universal dietary proof.

Ordinary scoped rewrite uses a fresh rewrite-profile session with original JSON,
not the creative-generation session/examples. Explicit quality repair can keep
its retained session. Rewrite profile says only exact requested action; no Mogodu
example is injected on an evicted rewrite. Existing prompt snapshot is deliberately
updated to verify this distinct profile, not loosened generative snapshots.

Generated validator flags saute/simmer temperature cues without oven/internal
method. Mixed saute-then-oven and internal temperatures stay out of this narrow
check. This is a clarification rule, not general cooking-temperature semantics.
Other rewrite requests have a no-new-temperature-without-request guard, but there
is NO general semantic proof of only-the-asked-change for arbitrary natural
language. Keep that residual limitation and #515 open pending exact F9 device run.

Eight new native methods: exact no-op vs compound ask/unknown stock, reported drift,
permitted substitution+metadata, partial substitution refusal, real backend no-op
before available/unavailable fallback, mixed oven nonfalsepositive. Python185PASS/
diffcheckPASS only. Swift/native/model/new UI pixels NOT RUN. Saved-card repair
control/toast and no-op before/after need actual device pixels. No Journal activation.
https://github.com/melusi-k/ate-ios/issues/515

Residual-cue review follow-up: no-op and accepted vegan results now share the same
conservative step/ingredient-note animal-or-unclear cue check. Explicit approved
plant-substitute phrases are masked only as whole phrases, never an entire step;
a later milk/chicken-stock cue still refuses. Exact step-only chicken-stock and
note-only animal fixtures added. Unknown stock remains a refusal, not certification.
