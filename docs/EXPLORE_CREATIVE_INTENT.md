# Explore suggestions: creative intent is not a recipe import

## Device finding and cause

On build 454 the owner opens Insights -> Explore new recipes and sees the import
verification refusal, with no suggestions. The screenshot's exact error comes
from OnDeviceBackend before model allocation, when `unverifiableSource` is true.

The app's own RecipeDiscovery prompt asks for similar tastes or ingredients, then
says the collection is data, not instructions. SourceRecipeFidelity.isRecipeShaped
recognizes any text with both ingredients and method/directions/instructions.
Thus even a normal one-recipe collection makes this app-created creative request
look like a malformed pasted recipe. It cannot be verified as an import and is
refused before the model. The native regression uses the actual assembled prompt
and actual recognizer, not a hand-written approximation.

The Settings 79358ms on-device diagnostic is not correlated to this Explore
request. It may describe another generation. It cannot prove this error was a
model timeout. Explore retains its existing 60-second deadline and late-result
revocation. Live model performance after repairing this earlier refusal remains
unknown and still needs device acceptance.

## Build comparison

- 450: tag 401406d5007a311c2aa1b0fa99008b12c828e56a, no isRecipeShaped guard.
- 451: tag 0811f5f808db7c8da14f436a81670518bafd4640, still no guard.
- 452: tag 353efaad8f896263d7538d3bf9d94d91799f741f, #607 adds that guard.
- 454: tag cce94c10a44406d3afe80bd8f71b18382d6bb8cb, retains it.

RecipeDiscovery and SuggestedNewRecipesView are byte-identical between 450 and
454. This collision was introduced with the source-bound import changes in 452,
not with the later Library/Add/Detail/Cook stack.

The earlier 450 screenshot showed saved Library Explore rows with compressed
metadata. The owner's 19 Nov 02:47 message (phonemsg-01M7RMAZKEK177D66SP7W5YX7B)
asked where new LLM suggestions were, since he expected unsaved/uncooked ideas.
The ensuing conversation distinguished that saved-Library sheet from Insights'
new-suggestion screen. That is NOT a recorded successful model generation on 450.
The source comparison establishes this regression, not an invented prior pass.

Release sources:
- https://github.com/melusi-k/ate-ios/releases/tag/build-450-TierA
- https://github.com/melusi-k/ate-ios/releases/tag/build-451-TierA
- https://github.com/melusi-k/ate-ios/releases/tag/build-452-TierA
- https://github.com/melusi-k/ate-ios/releases/tag/build-454-TierA

## Repair

A typed RecipeDiscoveryGeneration can be constructed only from collection context
and prior suggestions. The session passes it to OnDeviceBackend.suggestRecipe,
which explicitly selects creative generation inside the private backend path.
No serialized ParseRequest flag, user-entered marker, prompt substring exception
or relaxed import recognizer selects that path. Ordinary Prompt, URL, Image and
Rewrite entry points keep their existing source-recognition behavior. An ordinary
paste of the exact discovery words still fails closed before model or fallback.

The typed path skips only source-paste recognition for the app-created request.
Model cancellation, the prompt-size bound and the actual generation engine stay
in place. Discovery still requires on-device availability, rejects Demo output,
rechecks current owner/history/duplicates/quality and writes only on explicit Save.
Errors get a clear retry message and empty-state action says Try again. There is
no automatic retry or deadline change.

Original backend/discovery/view byte contracts are preserved by an exact inverse
before the existing historical assertions. All original assertion hashes and
import fixtures remain untouched. Changed/missing/duplicated fragments fail the
new inverse. The source recognizer itself is byte-identical to main.

## Tests and limits

Three new native tests exercise the actual pre-model backend boundary:
1. Actual assembled prompt is recognized as an unverifiable import, while typed
   discovery reaches the existing generation boundary with the original prompt.
2. The exact same text pasted as a normal request still fails closed before model
   or fallback.
3. A real OnDeviceBackend with model unavailable cannot publish its Demo fallback
   through the discovery session; the session exposes retry and saves nothing.

The unavailable-model fixture is explicit, not proof of live Apple Intelligence
output. All three tests are added to required full-unit pass names. Existing
session tests retain exact quality/owner/duplicate/cancellation/deadline checks;
only the callback type and exact improved error expectation change. Prompt mode
is now asserted at the real backend boundary rather than the old callback stub.

Four Python tests cover exact inverses, typed routing, retry/safety and required
native names. Swift compilation, native unit/UI execution, retry pixels and live
model/device suggestion acceptance remain UNRUN. Python is not native proof.
No timeout, allowance, retry count, workflow, job or budget was changed. This is a
separate branch off main cce94c10, not part of the four-screen stack. Reviewer
owns publication and qualification.
