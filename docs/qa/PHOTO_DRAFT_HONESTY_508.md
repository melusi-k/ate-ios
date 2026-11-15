# #508 photo draft honesty

Base: main `4aa5e5ed62c84cba4bb9a9008ae35810956d91ae`.

An uncertain photo question no longer asserts that the image is a spread of several dishes. The existing selection route, chips and one-or-many choices remain unchanged.

After model generation/repair and final photo confidence calibration, low-confidence photo guesses omit cuisine and tags. Those fields are not evidence that an uncertain orange drink is a South African main. A short note states why they were omitted. The recipe, dish title, ingredients, steps, confidence, alternatives and existing confirmation rules stay unchanged. Other sources, at-threshold/high-confidence guesses and historical cards without confidence are untouched. Applying the rule twice does not duplicate the note.

Six native unit cases cover scope, exact content preservation, threshold, other sources, missing confidence, idempotence and question wording. Local Python tests reconstruct the exact backend base and retain original OCR fixture hashes. No OCR recognition, deadline, input, assertions, waits, timeout, retry or workflow changes.

Native compile/XCTest, real-model generation and pixel verification are UNRUN. Reviewer must run PhotoDraftHonestyTests and the existing photo regression suite, then inspect normal-text iPhone 18 Pro pixels for the ambiguous orange-drink question and low-confidence draft. Device acceptance of #508 remains open until that evidence exists. This source patch does not claim that visual identification is now accurate or that high-confidence cuisine tags are semantically proven.

Source PRs close only after the reviewer confirms the destination commit; branches kept.
