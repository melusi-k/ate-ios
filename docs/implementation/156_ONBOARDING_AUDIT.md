# #156 bounded historical audit fixes

Incremental on corrected #82 header1f360ec. No extra PR/runner/dispatch, no audit
category filter change, no timeout change. Normal-text owner acceptance remains;
physical VoiceOver/Reduce Motion is separate, not claimed by CI.

## Direct historical evidence

Downloaded/read original4912b086 run39710638199 Accessibility uitest.log and
unpacked its Zstandard audit attachments. Onboarding names precisely:
- onboardingSkip button: hit area too small
- Any recipe, one clean card: text clipped
- feature body paragraph: text clipped
- decorative wand.and.stars image: label not human-readable

Current main527dfb6 still has that unframed Skip, unconstrained feature text, and
exposed system-symbol image. Candidate gives Skip44x44 minimum, lets title/body
grow vertically, hides only that redundant decorative image from accessibility.
It does not hide meaningful content, filter audit categories or skip the screen.
The onboarding test now fails if the page does not appear instead of silently
passing without auditing, and asserts the Skip target dimensions. The audit
helper adds keepAlways screenshots through defer, including failure paths.

Original MainScreens audit also reported unlabeled Other on Library, Cook
Progress hit area, Back/Next Dynamic Type categories, Library demo-note/time
clipping, Shopping input clipping, then dead More-tab navigation. Current test
already routes Settings instead of More. This candidate does not pretend to fix
unidentified Other or all MainScreens findings. Those require exact current
native audit output and pixels before further app changes.

Sources:
- https://github.com/melusi-k/ate-ios/actions/runs/39710638199/artifacts/12398050245
- https://github.com/melusi-k/ate-ios/actions/runs/42610132681/artifacts/13672083398
- https://github.com/melusi-k/ate-ios/actions/runs/42610132681/artifacts/13671793321

Later740f81ad/run42610132681 focused regression logs do not execute either named
MainScreens/Onboarding method. Its green cannot be used to dismiss these failures.

Python185PASS/diffcheckPASS only. Swift/native and actual new pixels NOT RUN. Full
current exact-head AccessibilityAuditUITests remains required; this is a bounded
candidate, not #156 completion. No production Journal activation.
