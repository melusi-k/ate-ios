# Nonblocking timer notification submission

## Proven failure

The original #622 unit artifact on 487fdafe and the repaired #622 artifact on
e858daec contain watchdog stackshots with the same synchronous main-thread path:
WidgetBridge kitchen relay -> TimerCenter.startQuick -> TimerAlerts.schedule ->
TimerAlerts.cancel -> UNUserNotificationCenter.removePendingNotificationRequests.
The repaired capture resolves the system stack through notification-service XPC
and a synchronous reply wait. All 284 samples in that capture, and all 252 in the
original capture, occupy the path. The relevant extracted frames are retained in
`diagnostics/timer-notification-stackshots.txt`.

The repaired run eventually logs LiveActivity creation and returns from kitchen
at 281.375 seconds. Its late 282.133-second test PASS does not erase the 240-second
watchdog failure. Older retained runs returned from this same kitchen interval in
58.452 seconds and about 220 seconds. Those older logs have no in-call sample, so
they show the slow interval but cannot prove the exact blocking frame.

This path is byte-identical on main cce94c10 and both Library heads. The defect
predates Library selection. Timer persistence, watch update and widget reload
precede the sampled notification cancellation and have already returned there.
The AppShortcut metadata error is correlated noise, not the proven blocking call.
DraftInputAttempt's earlier timeout did not repeat: it passed twice on e858daec,
in 0.003 and 0.005 seconds. No speculative DraftInputAttempt repair is included.

Sources:
- https://github.com/melusi-k/ate-ios/actions/runs/44555617177/artifacts/14548317588
- https://github.com/melusi-k/ate-ios/actions/runs/44568752959/artifacts/14555204122
- https://github.com/melusi-k/ate-ios/actions/runs/44507914300/job/135504289247

## Repair and ownership

TimerAlerts now admits work to one process-local serial background worker. It
keeps the real notification-center calls. A stalled synchronous cancel can block
that worker, but cannot hold the main thread or the timer writer lock. Each
replace still cancels the same ID before adding. The next operation waits for the
add completion callback, preserving replace/stop order even when add is delayed.
The remaining relative interval is computed after cancellation returns, using the
original absolute deadline and one-second minimum. Alert title, body, sound,
quiet-hours policy, identifier and time-sensitive level are unchanged.

TimerCenter remains the admission owner: its writer-boundary effect synchronously
enqueues the operation. No worker holds that lock across IPC. Clear-all's existing
reset owner submits removal and verification through the same FIFO and awaits it.
All already admitted schedules complete before that removal. Pending AND delivered
notifications are removed, followed by the same single 300ms settle and real
read-back. A failed read-back returns false. No older queued add remains behind a
successful clear barrier. The owner still fences after the await, as before.
No call sites or writer/reset ownership rules changed.

A daemon that never responds can still delay alert effects and clear-all
verification. This repair does not invent successful delivery, bypass permission,
retry, increase any allowance, or promise daemon health. As with other asynchronous
notification submission, process termination before execution can prevent queued
work from reaching the service. Actual alert delivery and suspension behavior
still need native acceptance; a responsive timer UI alone does not prove delivery.

## Tests and limits

Three new native unit tests exercise the production worker with deliberately
blocked synchronous cancellation and held add completion. They prove caller return,
cancel-before-schedule/stop ordering, clear-after-add ordering, failed verification
remaining false, and cancel-only never adding. These are controlled dependency
blockers, not OS delivery tests or instant-success substitutes for the stall.
The existing real-system widget-relay test is byte-unchanged and additionally
required by name in the full unit pass ledger. All three new names are required.
No workflow, existing native test, timeout, execution allowance or retry changed.

Four Python wiring/source checks supplement the native tests. Python passing is
not Swift or notification-service qualification. Swift compilation, all three new
native tests, the unchanged actual widget relay, real notification scheduling,
clear-all native regression and app suspension acceptance are UNRUN here.
