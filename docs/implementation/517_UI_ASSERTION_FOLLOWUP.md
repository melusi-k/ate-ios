# #517 UI assertion follow-up (incremental on1cd03624)

Run43302044080 source7ee50cad, Xcode27.1, iOS27 simulator
0A1B5EC5-2485-4F8E-B06B-1185D8E186C0. Native failures remain failures until
normal exact-head qualification proves the candidate. Not stall-rule eligible.

## Repair button: runtime accessibility identity defect

Attached transient-generation-retry log shows the exact hierarchy:
Button identifier draftNeedsInput label Repair these gaps, and second Button
identifier draftNeedsInput label It's right, let me save. The missing repair
query was not evidence that generation failed or repair feature was absent.
The enclosing VStack's identifier propagated over both child button identifiers
on this runtime. Move that identifier to the noninteractive heading. Original
repairDraftQuality and confirmDraft action IDs stay on their own Buttons.
No fixture, quality rule, Save gate or production repair behavior is changed.

Existing UI test still waits15seconds, taps actual repair and requires the gap
button to vanish within15seconds. Added strict distinct-action count assertions,
Save disabled before/Save enabled after and confirm action absent after. This
cannot pass merely by removing the repair button. A screenshot is retained before
the identity query so a future failure still yields pixels.

## Journal after Settings scroll: harness reveal setup, not relaxed navigation

Log: Shopping/Settings title and logo assertions pass, then Settings swipeUp,
Settings title still exists, TabBar exists, Journal Button missing. No PNG or
full nav hierarchy supplied, so exact minimized shape is unverified. Source
explicitly tabBarMinimizeBehavior(onScrollDown). Test never revealed chrome after
its scroll. Add ONE reverse swipe on the caller-owned Settings Form before the
same strict Journal tab path. No repeated tapping, back navigation, coordinate
shortcut, tab policy/layout change, wait increase or skipped assertion. Assert
Settings is still selected and retain before/after reveal screenshots. Every
Journal existence/hittable/selected/root/oneheader/logo/content/addentry assertion
and scroll check remains. New failure means investigate, not fallback elsewhere.

## Visual/evidence limits

Inspected supplied contact image: middle panel has Tomato bread salad, missing
bread ingredient and disabled Save, with review scrolled down. It does not prove
the repair action is absent outside the crop; the AX hierarchy diagnoses its ID.
No nav PNG. No fresh simulator/pixel execution is available here; changed AX IDs
and chrome-reveal setup are SOURCE candidates, not visually verified fixes.
Reviewer needs exact-head repair before/after screenshots and Settings/Journal
screenshots before accepting runtime/UI outcome. No user device claim.

Python source-preservation checks only. Unit named-pass list remains original25+
prior9 from1cd03624; no new XCTest method or broader tail names added. Existing
required UI methods remain unchanged by name and no timeout is raised. Food
Journal activationOFF; no publish, self-approval, merge or dispatch by Builder.
