# Activation slice: watch activation republish gate (OFF)

Builds on1e8a998c. PhoneWatchBridge.activationDidComplete previously called push
outside its writer boundary, treating session/timer handoff as read-only. It now
calls republish(), a gated effect. A retired writer no longer directly sends the
cached session just because WatchConnectivity finished activating later.

This is NOT immutable callback capture: writerBoundary is still mutable and the
shared bridge must NOT be rebound while old callbacks can run. Production host must
retain per-graph bridge identity or supply a qualified callback/session epoch plan,
clear cached data and stop/verify mirror work at retirement. Watch's separate disk,
OTP session and generation-aware sync remain independent required work. Delivery to
Watch is not claimed or verified.

One native test checks republish attempts the boundary and no effect runs on refusal.
Native compile/tests and paired-device handoff UNRUN.191 Python tests PASS. No
production binding or app route changed.
