# Access-lost await phases

On90559a43 full-unit job137020311314, testAccessLostDuringWordingAndNewEmptyEvidenceClearWithoutPublishing exceeded240s with no source assertion. Previous passes onb406/ed82 were0.002/0.003s; older retained passes0.002–0.390s. The23:39:55–23:40:00Z sample shows XCTest async invocation/XCTWaiter, with no test-specific Swift await exposed. It does not establish a fixture or product cause.

Add ten fixed BEFORE/AFTER stamps around the five existing wait chains in this one method, reusing the existing monotonic stdout helper. First unpaired accesslost-before identifies its await boundary. Original statements remain byte-identical. No new helper, synchronization, actor annotation, timer, polling, assertion, timeout, or product change. Exact inverse restores the whole source before the earlier late-prompt diagnostic inverse; the earlier fixture hash stays unchanged.

Native validation is pending. A pass is non-reproduction, not a fix. Draft test passed0.010s on90559a43; Journal and Dogfood green remain evidence for that head. Full-unit and account reds remain real. No retry or merge.

Source: https://github.com/melusi-k/ate-ios/actions/runs/44960803523
