# Add Prompt requires recipe source

## Device finding

Build454, typed Eggs Benedict, two runs at20:14 and20:16. Inspected all six
screenshots. Both completed review cards at20% confidence with Save disabled,
but ingredients and steps differed. First showed tomato/onion eggs; second
butter-poached eggs and milk/cheese sauce. Both could be confirmed for Save.
These are completed invented drafts, not evidence about the paste/link hang.

The25minute header and10minute prep note on the first card do not by themselves
prove a timing arithmetic bug: prep and total are different quantities. The
source defect is already established without treating that difference as one.

## Proven source route

On454, SourceRecipeFidelity.extraction returns.none for an ordinary dish name.
OnDeviceBackend's prompt branch then uses RecipePrompt.prompt for creative
generation. Confidence and later confirmation gates act after the card exists;
confirming a name gives no ingredient or method evidence. The separately reviewed
Prompt repair conditions the name, but intentionally does not invent a source.
Thus title conditioning alone cannot fix this device finding.

## Minimal change

AddPromptSourceImport is the actual Add primary backend boundary. It checks
cancellation, then refuses a Prompt whose extraction is.none before invoking ANY
backend, including demo/custom backends. It asks for full ingredients/method,
a recipe link/screenshot or manual entry and points new-idea requests to Explore.
No dishHint, confidence or confirm-to-save bypass. No returned card, preview or
invented ingredient set. Existing pending input and ErrorRetryCard remain; a
retained question cannot mask the error because the parent deadline packet gives
errors priority. No navigation/automatic Explore action is added.

Verified recipes pass unchanged to the backend with their original text/hint.
Recognizable.unverifiable sources keep their existing backend fail-closed error.
Link, image and rewrite requests retain their existing routes. This is an Add
Prompt policy, not a global ban on deliberately creative generation. The separate
typed Explore path and its gates remain byte-identical. Plain recipe paste can
still await its model and uses the parent's60second terminal deadline.

Input copy and button now describe pasted-source import rather than promising
new-idea generation. Search/other entry points that prefill Add with a name
will receive the same honest refusal; they cannot silently generate there.
Food-photo behavior is unchanged and remains explicitly described as a guess.
No claim that all source-less routes elsewhere in the app are solved.

## Stack and verification

Branch fix/add-prompt-source-forward starts at deadline packet head
7bf711c7f136ba86981be495cefce655a122d7e7. That head carries the ordinary merge
of actual627/628hosted sibling heads, then deadline/local-history changes.
No older main-based replacement. All previous runtime source except Add view is
byte-carried. Original inverse helpers/fixtures remain unchanged. A new exact
Add-view inverse restores that exact deadline parent before older assertions;
new raw-source assertions require the pre-backend gate and actual call wiring.
No old test assertion removed or historical hash replaced.

Five required native boundary tests cover both typed-name/idea refusal including
confirmation, byte-exact full-source forwarding and real no-demo gate,
unverifiable-source refusal in real backend, unaffected non-Prompt routes and
terminal cancellation. Three new Python checks cover exact inverse mutants,
actual Add gate/copy/wiring and native required names/Explore separation.
Native compile/unit/UI and real device refusal pixels remain UNRUN. Python tests
are not Swift or device qualification. No live-model claim is made by mock tests.
No timeout raising, retry, source/quality/Save relaxation, new screen, publishing
or production write.
