# Diary entry screen receipt, test-local only (default on)

Base d21fd1cf5022a953b3ec8582b4ebd16892b504cd. Native and pixels UNRUN.

Separate from the five-site sync fixture correction. This branch does not
include that correction. Only testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch
gets a DEBUG+UITesting receipt enabled for this single test by its existing
-UITesting app launch argument. No environment opt-in, CI/scheme changes or
new forwarding needed. No other test gets this receipt.

Phase1 before original first openDiary;2 after it. Phase3 before original
relaunch openDiary;4 after it. Each prints numeric phase+monotonic uptime,
takes a keepAlways screen screenshot, then prints screenshot-return. No AX
queries or keyboard probes added. No full hierarchy or text values logged.
The original steps remain byte-for-byte in order. Shared openDiary,
scrollToHittable, bottomClearBound and keyboard queries are untouched.
This brackets the helper, NOT immediately the internal keyboard.exists.
The extra screen operation may perturb timing or stall, indicated by missing
screenshot-return. Existing native timing limits and failures still count.

Current native log stalls in FIRST openDiary: Settings diary frames24..31s,
keyboard.exists36.95s, retries68/99s then cap263s at line124. It has not reached
form saves or relaunch, so this cannot prove those product semantics failed.
Other test/head passes do not qualify this exact head. Runner XCTWaiter is
not proof of app-side cause. Existing nutrition attachment export already
retains keepAlways attachments; no extra job, export, runner or retry.
Native Reviewer must inspect phase1 image, phase progression and final gate.
Screenshots may not exist if capture itself or earlier launch stalls.

Source PRs close only after Reviewer confirms destination commit; branches kept.
