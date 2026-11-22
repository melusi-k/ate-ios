# Sample the first Library idle stalls

Exact-head6bd731f8 Group28 is RED at240s;90559a43 passed101.561s. First Browse tap:61.664s vs3.150s. First Sort submenu:62.330s vs2.188s. Red logs two60s animation-completion notification waits; latest green has neither. First sorted-list screenshot172.18s vs41.40s, final Add-to-shopping tap239.29s vs98.31s. Older green also had the two60s waits, so they are a failure risk, not a new product-cause finding. Late context-menu screenshot shows Zesty tacos menu correctly open; late sample does not cover the earlier debt.

Wrap the unchanged native command with a diagnostic observer of its existing log. Only the first Group28 Browse and Sort-submenu phases can arm it. At10–30s from an open phase's host monotonic timestamp, capture3s samples of the uniquely matched simulator app and runner, at most four sample invocations. Closed/old buffered phases do not trigger. PID lookup is scoped to the selected simulator's executable paths; missing or ambiguous matches and sample failures are recorded. No app/test/selection/assertion/allowance change. No native output rewriting, pass inference, restart or retry.

The observer joins when xcodebuild ends, including failure; any in-flight subprocess is bounded. SIGTERM/SIGINT forward to the child and stop observation. The native exit code propagates to the existing shell failure handler unchanged. Artifacts add only dogfood-idle-samples. Python tests cover actual child statuses0/1/65, exact output and joined receipt, phase bounds/staleness, simulator PID scoping, and sample errors. Native macOS sample success is UNRUN. Sampling adds overhead and may perturb timing; a pass is non-reproduction. Empty/missing samples cannot establish idle state or app health. If the child has no fresh phase stamps, it is not sampled.

The workflow exact inverse is pinned; all original selections, workflow timeouts and native240/480 allowances remain untouched. Prior reds stay red. No merge.

Sources:
https://github.com/melusi-k/ate-ios/actions/runs/44964674492
https://github.com/melusi-k/ate-ios/actions/runs/44960803536
