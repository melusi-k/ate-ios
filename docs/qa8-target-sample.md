# QA8 targeted stack diagnostic (test-only)

Base: hosted #539 `1ccf1ce87db8cdb56a576024c591bbbb5cc87af7`.
This packet is diagnostic, not a product fix or native qualification.

The existing DEBUG + `-UITesting` + `-qaQA8ExitFileDiagnostic` app markers
remain unchanged. The Dog critical-flows invocation starts one external
observer, polling these two numeric cache files at 5-second intervals for
at most the existing 30-minute step window. Only files modified after the
observer starts are eligible. An `exit-return` row, matching PIDs, a utility
`scheduler-fired` row at least 5 seconds after exit, and at least 4 seconds
since the latest MainActor row are required. Healthy MainActor deliveries
prevent this trigger. A missing report is not evidence of a healthy app.

Before capture, `ps -p PID -o comm=` must return an absolute executable path
under the selected simulator with the exact `Ate.app/Ate` suffix. A failed
identity check stops capture with a retained status, without retry or sudo.
The observer invokes `/usr/bin/sample PID 3 10 -file ...` once: 3 seconds,
10-millisecond intervals, one selected process. It does not invoke spindump,
sysdiagnose, host-wide enumeration, private APIs, a debugger, or other-process
stack capture. No heap, model contents, tokens, user text, or app database is
requested. A standard process sample can contain all target threads, loaded
images, paths and addresses. The main-thread subtree must be identified in
the returned report; this is not a main-thread-only sampler.

Sampling briefly suspends the target at each sampling point and can perturb
timing. Do not use the sampled run as proof of unperturbed performance.
The sample collector is killed if it exceeds 15 seconds, with no retry.
The shell's existing exit-window marker is preserved and the observer is
terminated/joined on step exit; its signal handler also terminates an active
sample process. No test assertions, selections, retries, qualification rules,
workflow limits, or execution allowances are changed. No app Swift changes
or focus fingerprint refresh are needed.

`qa8-target-sample/` is retained with the existing Dog artifact. Check:

- `status.txt`: trigger PID, times, return code, timeout or unverified state.
- `trigger-main.txt`, `trigger-scheduler.txt`: exact numeric trigger evidence.
- `sample-command-status.txt`: command errors, including access denial.
- `qa8-ate-only.sample.txt`: target stack report, if actually produced.

A zero command status alone is not a verified stack. Confirm the report's
PID/image identity and Main thread frames before drawing conclusions. If
permissions fail or stacks are missing, report the missing evidence. Do not
escalate privileges or call the stall's cause proven.

## Sources

Apple documents a selected-process, three-second sample:
https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/mac

The sample(1) manual mirror documents PID, duration in seconds, interval in
milliseconds, `-file`, all-thread call stacks and brief target suspension:
https://www.manpagez.com/man/1/sample/

## Evidence status

Native execution and actual sample capture: UNRUN in this packet. Linux
validation covers observer selection/identity, mocked single-shot execution,
cleanup, unchanged XCTest/app sources, YAML and shell syntax, plus the Python
suite. It cannot establish macOS sampling permission, simulator executable
path format, stack quality or the cause of QA8 MainActor unavailability.
