# #512 named-dish reconstruction provenance

Base: main `4aa5e5ed62c84cba4bb9a9008ae35810956d91ae`.

The supported named menu/advert path now adds an app-owned provenance notice even if the model omits it. It applies only when existing caption analysis finds promo text without recipe signals and the regional glossary recognizes a dish. This narrow detector does not certify arbitrary text, plain dish prompts, screenshots or unknown names.

The note says that the menu/advert supplied no source recipe and that ingredients, quantities and method are suggestions. A shorter description notice persists on the saved card so provenance does not vanish after the draft screen. Existing description and model notes are retained. Repeating the rule does not duplicate either notice.

The draft confidence label explicitly says "Dish-name confidence" and "no source recipe; ingredients and method are suggestions". The existing score measures dish identification, not recipe fidelity. The patch does not arbitrarily lower that score: doing so would force another identification question and could lose original-link context during regeneration. No confidence or confirmation threshold changes. Other recipes retain their normal confidence wording, with a regular separator.

Provisional streamed previews are suppressed for this recognized reconstruction path until the source notice has been attached. Final recipe content, quantities, method, source and confidence are not rewritten. No second model call, OCR/deadline/input/assertion/wait/timeout change, paid runner or workflow change.

Seven native unit cases cover the exact F3 caption, measured-recipe/non-menu exclusions, idempotence, preserved recipe content/confidence, missing confidence, source-qualified confidence wording and no copied private promo details. Source contracts reconstruct the exact original backend and freeze original OCR, prompt and QA input fixtures.

Native compile/XCTest, real-model output and pixels are **UNRUN**. Reviewer must run NamedDishProvenanceTests, rerun F3 with the real model, inspect normal-text iPhone 18 Pro draft confidence/note and saved-description pixels, and verify ordinary recipe confidence text. #512 device acceptance stays open pending that evidence. #538's experimental early-return generation tool is a separate held branch and needs the same policy reconciled before it supersedes this path.

Source PRs close only after the reviewer confirms the destination commit; branches kept.
