# #509 bounded source screenshot import

Incremental on timev3/quality stack73b4e5f. Source-only candidate, no publication.

Inspected the actual source image IMG_5009 pixels, not only the issue text:
Creamy Samp has explicit Serves6, Ingredients, four numbered Method steps and a
separate HINTS & TIPS section. Ingredients wrap the cream-cheese name, and two
conversion-control labels sit between ingredients and method. No soaking appears.
https://github.com/melusi-k/ate-ios/issues/509
https://cdn.linqapp.com/attachments/partners/4e635ebb-d328-59f6-9d87-be1a13a739ca/983d0dbd-2bcf-4532-9694-ea1f4ae18ada/IMG_5009.jpeg

Candidate bypasses BOTH model and Demo fallback for detected text screenshots,
even when user supplied a dish hint or model is unavailable. A deterministic,
bounded OCR section parser imports only clear title/Serves, measured ingredient
lines, sequential numbered method. Wrapped lines retain source words; the two
known conversion labels are recognized controls, not ingredients. Tips/variations
remain a note, never steps. No inferred prep, nutrition, duration or paraphrased
description. Source cooking time inequality is not fabricated as a specific total.
Unsupported headings, missing servings, partial ingredient/step boundaries,
nonsequential method, unsupported quantities fail closed with an actionable crop/
manual-entry error, not a creative recipe. No broad OCR-layout capability claim.

Source is Imported rather than Made with Apple Intelligence. Copy explicitly says
detected text must be checked against original, no longer promises unqualified
word-for-word Vision accuracy. Existing synthetic OCR image is extended with
Serves and Method so it follows the same source contract. OCR injected only for
native backend tests, default remains real bounded Vision.

Six native methods cover source samp quantities/order/no-soaking/four steps,
tips exclusion, no inferred total/description, missing boundaries/servings/step
sequence, no tips, and actual backend model-available/unavailable plus hint paths
with zero fallback calls. Native Swift/Vision/device/new UI pixels NOT RUN.
Python185PASS/diffcheckPASS only. Real IMG_5009 Vision roundtrip still required;
this deliberately trades unsupported-page success for no fabricated source facts.
Photo with extensive printed text may classify as screenshot under existing
heuristic and refuse unsupported structure; do not call that a full photo fix.

Do not close #509/#35 from this packet. Reviewer must check actual current OCR
output, existing photo/screenshot UI journeys and source/result side-by-side pixels.
Activation remains OFF; no rollout change.

Review follow-up: servings reads the entire declaration value, including a
separate next-line value only when wholly numeric. All Serves declarations are
counted; ranges/fractions/composites and adjacent numeric/range continuation
refuse. Split terminal numeric step markers (4./4)/4 on their own line) refuse
rather than merging into the previous step. Native regressions include each.
Restriction unchanged: ANY text detected as screenshot text bypasses both model
and fallback, even with a user dish hint, and unsupported text-heavy photos refuse.
