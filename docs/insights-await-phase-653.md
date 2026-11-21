# Insights ownership await phases

The first normal ed82b8b8 full-unit run failed testLatePromptCannotPublishAndOldDeferCannotStopNewLoading at its unchanged240s allowance, with no source assertion. Older greens were0.020–0.546s. Sample21:00:08–13Z shows XCTest waiting with idle app main, no Swift async task boundary. This is not an AX test and does not select the changed Journal UI test.

Fixed-count diagnostic:12 monotonic BEFORE/AFTER stamps around the six existing fixture/task waits in that one method. The first unpaired BEFORE names the blocked await. No scheduling, actor isolation, continuation helper, assertion, timeout, timer, polling or product implementation changes. Resume-plus-await statements remain byte-identical; no additional waits are introduced. The original test and both fixture classes are recovered byte-for-byte by the exact inverse guard.

This diagnoses the next changed candidate's first normal result; it is not a root-cause repair. A pass remains non-reproduction. Native proof is pending. Current RED remains RED; builder does not merge.

Evidence: https://github.com/melusi-k/ate-ios/actions/runs/44945466128/job/136972813880
