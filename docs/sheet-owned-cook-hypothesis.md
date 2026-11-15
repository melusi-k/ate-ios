# Preserve Library recipe sheet beneath Cook

Base775948c5c51c065fae3284c6da4124c3060c8b28. Native UNRUN.
Exact retained Account test06b fails after Done at line279. Inspected contact
pixels show completion before tap and Your Kitchen after tap, not recipe
detail. Same log's pushed-recipe completion returns to Cook mode successfully.
No phase19..25 console receipts found in supplied archive. Earlier534Done
failures differ: absent button or delayed dismissal, not this proven root.

Recipe detail currently requests a root fullScreenCover while its Library
origin is already a sheet. Hypothesis: competing presentation owners discard
the origin. Add optional onCook closure to RecipeDetailView (default retains
root behavior). ExpandableRecipeDetailSheet supplies it and presents Cook
using its own fullScreenCover. Dismiss Cook only; keep original detail state
and detent underneath. Fullscreen chosen rather than navigation push so
preview collapse/close chrome does not remain above Cook. Existing
JournalBoundCookMode and modal-dismiss/reflection handoff retained.

No tests, assertions, waits, fixture outcomes, workflows or allowances changed.
No root destination fabrication, path reset or delayed re-navigation.
Two product files changed, plus strict source contracts/docs/focus metadata.
Native must prove saved-sheet final Finish/Done returns same detail, ordinary
Exit, pushed-detail route, resume, landscape, timer/footer clearance, Add a
note routing and dismiss. Root-owned note composer over retained recipe sheet
is an explicit unverified area; this packet does not claim that path fixed.
No source evidence proves framework root cause; source-only hypothesis.
No native screenshots of changed behavior available. Existing screenshot is
baseline failure evidence, not acceptance. Nutrition allowance exception is
untouched and not investigated. SettingsAbout allowance remains separate.

Source PRs close only after Reviewer confirms destination commit; branches kept.
