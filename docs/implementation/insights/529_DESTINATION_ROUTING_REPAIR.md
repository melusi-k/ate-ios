# #529 seeded destination native-red repair

Base:97ed1c692ad816ad8121deef431bc5a098519a43.
Presentation job131882913799 on529 found Food diary absent after action (line508)
and Journal tab button absent on Shopping return (line467). Shopping navigation,
seeded pending row and count assertions had already completed; this is not a
failure to compute a shopping candidate or open the list.

Diary previously depended on a boolean onChange inside Settings: a true value
set before first mount need not generate a change event. The contextual action
now sets the real typed settingsPath to exactly one nutritionDiary route before
selecting Settings, clearing the old boolean. Repeated opens replace old routes.
Shopping similarly opens its explicit root. Pushed Insights clears its typed
Journal path instead of racing environment dismiss animation across a tab switch.
Cooking-history in-place scrolling is unchanged; modal/root dismiss retained.

Shopping can minimize iOS26 tab chrome after content movement. Test now performs
one downward gesture in actual Shopping ScrollView before its single Journal tap,
asserts the Journal button and captures revealed chrome. No retry/conditional tap,
new wait, timeout increase, deleted assertion, fake candidate or fixture change.
All existing evidence/destination/seeded-content/retention checks remain strict.
Two required native unit methods test diary path replacement/idempotence and
shopping root selection without collateral path changes. Full prior required
union retained; one Python source contract added. No workflow changes.

Nutrition comparison: current job131882913908 raw log has CookPlan save idle stall
at34s, no idle notification95s and4min expiry; diary editing reaches quantity and
Edit food nav query at238s then4min expiry. Earlier retained logs have both exact
methods passing45.102/57.721s and109.141/111.360s. Older496 sourcec4cfa1b1 from
run43358802734 has unchanged CookPlan/NutritionDiary UI test files, CookPlanSheet,
NutritionDiaryView and CookPlan logic versus529. This does not prove these exact
stalls pre-existed or exonerate529; no new product defect is established. No
speculative nutrition patch; current reds remain unqualified and need diagnosis
if repeated. No pass, waiver or quarantine inferred from other runs.

194PythonPASS, Swift grammar/diff-checkPASS. Native build/typecheck/warnings,
routing units, seeded UI and pixels UNVERIFIED until exact-head execution.
Build-focus metadata intentionally untouched: InsightsView blob changes, requiring
reviewed hosted runtime then separately independently reviewed focus update before
native CI. Guard stays strict. No dispatch/push/merge/activation/issue closure.
