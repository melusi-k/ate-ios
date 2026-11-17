# Inset-independent detail host: layout feedback hypothesis

Base #539 14e6c88b09ed3c2faf42703124d0adda57515ac6.
Native UNRUN. Branch-only, no waiver, publishing or merge.

The QA8 exit capture from PID63090 returns in 0.028s. Root chrome records
one minY value, 740. The detail host then alternates 760 and 740; its prior
reserve alternates 8 and 28. Quality/layout counts reach16384 around101s
after exit. Individual quality calls are usually1-2ms, max47ms in the
bounded capture. This is repeated evaluation evidence, not one long quality
call. Main stacks mostly show CA/SwiftUI hosting layout. Numeric atomic
writes and the sample may perturb timing. Group28/Reorder29 failures are
separate and not claimed fixed here.

The old GeometryReader wraps the content before safeAreaInset. That content
can be reduced by the bottom inset whose reserve uses its measured maxY.
The hypothesis is a closed geometry feedback loop. Move the existing
measurement and observer AFTER safeAreaInset so they wrap its outer host,
not its reduced content. This is only modifier order, not a new geometry
formula. Keep live chrome/host updates, reserve max(0,host-chrome)+8,
button/action/height, editing behavior, scroll content, diagnostics, native
tests and all allowances unchanged. No debounce, async delay, rounding,
monotonic max cache or frozen initial measurement. Parent-size/rotation and
chrome appearance/disappearance must still update clearance.

Source contracts reconstruct the entire original RecipeDetailView after
reversing only this move. A numeric example checks stable reserve for fixed
outer bounds and changes for different parent/chrome bounds; it does NOT
simulate SwiftUI or prove modifier geometry. Native pixels and original
QA8 footer/timer assertions are required before claiming no overlap or a
fixed hang. No native visual evidence of this patch is available here.

The earlier capture guard now composes that reversal before its original
baseline whole-file fingerprints. Its previous runtime git-show/git-diff
baseline dependency is replaced with exact original file/folder hashes,
including every native-test and Logic file. No missing baseline skips,
changed expected source or narrowed preservation scope. Tests run in a
one-commit checkout to validate that historical objects are unnecessary.

Focus must validate every evidence blob against BOTH actual source anchor
and destination after folding. Metadata pass is not native qualification.
Source PRs close only after Reviewer confirms destination commit; branches kept.
