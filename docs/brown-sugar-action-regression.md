# Brown sugar is not a browning action

Base: #534 hosted `bc45b9588799da4eb1c603eb9e6dfe28e5918ed4`.

The native unit assertion at GeneratedStepQualityTests line 50 is valid.
Its generated recipe is a main ("Vegetable curry") and its only instruction
is "Rub with brown sugar and garlic". That names ingredients, not a command
to brown anything.

The import-review change introduced a one-step-main completeness check in
commit `ea957683164c2cef57a03fc50aa8a730ff835f51`. It tokenized the raw
instruction and saw "brown", incorrectly emitting the unfinished-browning
warning. The later heat/time/doneness check already removed "brown sugar"
before looking for actions. The regression was inconsistent action
classification in the new earlier check, not a defective XCTest.

The fix shares that exact existing normalization as cookingActionWords.
Both action checks now use it. No broader exception, quality threshold,
recipe rewrite, guessed ingredient or test weakening is introduced. A
separate actual "Brown" or "Sear" action remains detectable even when the
same instruction also names brown sugar. Raw food-reference tokens remain
unchanged for ingredient-use validation.

The original test and all other original XCTest code are unchanged. Added
regressions cover the rub-only phrase, real browning with brown sugar,
searing ribs with brown sugar, a later bake action requiring time/doneness,
and an explicitly completed braise. Existing photo-review sear-only main
and source/cold-dish tests remain active.

Validation here is Python source contracts and Swift grammar only. Native
XCTest and the full original 1174-unit gate remain UNRUN until the reviewer
executes them on the destination commit. This packet does not qualify or
address the separate Account or Presentation failures. No publishing,
merging or PR closure is included. Source PRs close only after the reviewer
confirms the destination commit; branches kept.
