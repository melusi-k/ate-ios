# #513 bounded photo-choice/honesty increment

Incremental on corrected #5095b35d4d / quality stack, not a new PR. No publishing.

Question chips retain first three unique guesses, then editable generic Fish and
Vegetable dish choices. Both card-driven low-confidence questions and explicit
PhotoNeedsDish errors use the same helper; spread multi-card choices are unchanged.
Generic choices do not enter Vision labels or calibrate model confidence. Prompt
placeholder/help encourages the user to name sauce/garnish/side if desired rather
than confirming the suggested family without context.

Every final photoGuess card explicitly says it is not a whole-plate reconstruction
and unidentified garnish/sauce/sides were left out. This is the issue's honest
omission path, not a claim the system now sees roe/fennel. Current model input is
labels/OCR/scene cues, not guaranteed visible-component recognition. No unknown
component/quantity is fabricated to clear this issue. Existing named/label-based
component quality checks remain unchanged.

Five native choice/limit-note methods added. Python185PASS/diffcheckPASS only.
Swift/native/device/new UI pixels NOT RUN. Real F4 clear-fish-photo rerun must
verify choices + legible note and compare full plate; identification/ingredient
coverage improvement remains unproved. Do not call #513 closed from source tests.
https://github.com/melusi-k/ate-ios/issues/513

Scope follow-up: generic classes/help apply only to source.photoGuess questions
and image-mode explicit questions. Prompt-generated low-confidence questions
retain their original first-five alternatives, with an isolation regression.
