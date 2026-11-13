# Independent Library UI journeys

Source packet based on #530 head 79636cf3. No product changes, new mocks, retries,
new CI jobs, timeout changes or execution budget increases. Native UNRUN.

## Cross-run evidence

The reviewed retained-log comparison covers 32 Dogfood runs. Native 240s allowance
failures rotate between test28/test29 across heads, before #530. These are not a
new factory-specific signal. Both methods pass on other heads:

- #530 79636cf3 run43456526929: both exceed240s. Test28 continues after allowance
  failure and misses the final shopping toast around t314-324s.
- #529 23b17d48 run43448247164: test28 PASS144.094s; test29 allowance failure.
- #529 43589115 run43436698680: test28 allowance failure; test29 PASS187.615s.
- #526 3a0b1afa run43359137995: test28 PASS143.698s; test29 PASS185.591s.
- #493 198c3036 run43236214866: both allowance failures.
- Main's retained Oct30 runs41130563080/41122920318 did not select either method.
  They do not prove main passes or reproduces either failure.

Sources:
https://github.com/melusi-k/ate-ios/actions/runs/43456526929
https://github.com/melusi-k/ate-ios/actions/runs/43448247164
https://github.com/melusi-k/ate-ios/actions/runs/43436698680
https://github.com/melusi-k/ate-ios/actions/runs/43359137995
https://github.com/melusi-k/ate-ios/actions/runs/43236214866

The toast assertion occurs only once in the comparison. Artifact14058043173 has no
post-tap image or AX from that point: attachments stop before the240s allowance,
while the assertion is in the later continuation. Therefore a separate product
failure is unproven. Allowance fallout is the leading hypothesis, not a finding
that the toast works. Native screenshot review showed the retained Browse/Sort/
Group popup frames only, not the toast state.

For #530 test29, fixture setup ends around t67. Three native animation-idle waits
then each consume60s: Browse t68->128, Sort t131->191, long press t205->265.
This is a separate OS/runner symptom; the packet does not change product animation
behavior or assume a cause. Independent cases may still hit a240s allowance when
several such waits happen. No passing runtime claim is made.

## Scope and retained assertions

Test28 is separated into A-Z order, Recently added grouping, Cook time grouping
and returning to None, favourite swipe/feedback and Favourites-first order, and
context menu/Shopping feedback. The favourite case additionally asserts favourite
order rather than only tapping its sort option. Every existing popup uniqueness,
visibility and icon assertion in `pick` remains unchanged. Each case launches a
clean app and creates its own recipe(s) through the same existing UI path.

Test29 retains the accessible Move up journey with its initial newest-first and
final moved-up order assertions. The former best-effort drag is an independent
journey with its own initial order assertion and screenshot. This does not promote
that screenshot to verified drag ordering; it was capture-only before and remains
so. The packet does not remove an asserted drag result because none existed.

Shopping feedback still has its original3s existence assertion. Immediately after
that observation and before asserting, it records a screenshot AND full AX on both
success and failure. Diagnostics are deliberately not requested before observing
the short-lived toast, so capture latency cannot consume its2.6s display window.

Dogfood now selects all7 Library methods and requires EACH named pass plus at least
16 executed tests (9 existing KeyFlows +7 Library). The workflow still fails on
any xcodebuild failure, missing named pass or missing total. Same60min job budget,
240/480 test allowances, nonparallel execution and quarantine rules. Extra isolated
setup may increase wall time; qualification is needed before claiming a speedup.

## Local verification

204 Python tests PASS. Swift grammar and `git diff --check` PASS. Native build,
all16 selected UI tests and updated screenshot evidence UNRUN. No workflow dispatch,
GitHub publication or merge performed. Reviewer owns exact-head qualification.
