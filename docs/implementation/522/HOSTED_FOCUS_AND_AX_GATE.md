# Hosted source focus and required AX gate

Base/source anchor aaaf34f11fd8101b63ec13aad7c37b99d0a4883a. Runtime tree matches the reviewed 7539c039 candidate. This delta changes no runtime or UI test source.

Reviewed focus pins the existing hosted ancestor, retained app/Journal sources, and actual CookModeView/Components blobs. Summary keeps native/performance/pixel/VoiceOver qualification pending and activation OFF. build-focus.py's ancestry/stale-source guard is unchanged.

Compile's existing presentation-creation worker gets one separate required named invocation for RecipeStaticRowAccessibilityUITests.testCombinedRecipeRowsRetainQuantityNameStepNumberAndInstruction, same existing 180/240s allowances and unchanged job110min budget. Reject command failure, zero execution or missing exact named pass. Require its retained log and upload that log plus existing xcresult wildcard. Old journeys and their commands remain byte-identical. No new worker, retry or paid resource. Added routing source test. Native execution remains UNRUN here; publishing this delta arranges qualification, does not establish it.

Reviewer publishes branch-only; source PR closure after destination commit confirmed, branches kept.
