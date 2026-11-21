# Independent Dogfood QA and Library evidence

QA's nine required cases and Library's three required cases now run on separate
standard xcode-27 jobs. QA can upload its native results and finish while Library
is still running or red. This does not fix the Library popup animation-idle issue,
change the test journey or make QA success alone a Dogfood qualification pass.

The workflow freezes one full event source SHA. Both jobs check out that SHA and
verify it before work, select their own simulator, create their own build output,
and use distinct log/xcresult paths. There is no branch-wide workflow concurrency
rule, so the workflow itself does not cancel another same-branch qualification.
GitHub's account-wide runner limit may still queue any job. No paid/larger runner
or reserved concurrency is introduced.

Each required job keeps the original60m job ceiling and30m native step ceiling.
Both keep the exact240/480 test allowances and original xcodebuild command flags.
The exact original12-case union is partitioned9/3, without dropping or duplicating
any case. Original named Library console assertions remain, and structured
xcresult validation additionally requires exactly the expected unique Passed
case identities in each group. An empty, partial, repeated, skipped, wrong-name or
failed tree is red. Every group's last console summary must match its exact count
and zero failures, and all earlier summaries must have zero failures too.

A normal xcodebuild exit0 is necessary but insufficient. Nonzero status, allowance
failure text, fatal error, failed case, failed final verdict, missing bundle,
failed/timeout parser, missing final success marker or invalid structured results
cannot become a pass. A later pass marker cannot override an earlier failure.
There is no watchdog, teardown-success exception, nonzero-exit override or retry.
GitHub step/job timeout or cancellation blocks the aggregate even if some earlier
native output looked successful. Parsing is bounded at60s within the unchanged
step ceiling.

Each group uploads its log, structured results, verified case receipt and xcresult
before its source receipt. QA retains photo-phase diagnostics; Library retains
startup liveness. The source receipt is created only after required native checks
and diagnostics upload succeed. The existing dogfood-qualification context is an
AND gate requiring both job results successful with the same frozen SHA. The
existing Dogfood qualification result route gate stays intact. Every group has a
run-and-attempt-unique artifact name. No result from another run or source is
looked up as a substitute.

The existing Settings/account-sync QA7 diagnostic moves to an independent job.
It retains its15m test step ceiling,60m job ceiling, continue-on-error test policy,
original command and xcresult. It is still QUARANTINED / NOT A QUALIFICATION PASS
regardless of its own outcome, and cannot satisfy or block the required9+3 gate.
Its startup/build uses its own runner state. Its separate completion can lag the
required aggregate; the summary points to that independent diagnostic job.

Full units remain required separately by the Compile full-unit gate on the exact source.
This packet does not change Compile, app source, UI tests, Native test assertions,
repository rules, release gates or the meaning of native qualification.

Local verification includes actual subprocess simulations of the generated native
step, strict parser success/failure fixtures, contradictory logs, ordinary exit65,
termination-like nonzero exits, cancellation/wrong-head aggregate refusal, native
selector/flag preservation, shell parsing and a pinned inverse with mutation
rejection. These are local fixtures, not native iOS execution. Native final-head
compile/tests and hosted workflow execution are UNRUN. Do not call this a build
candidate until the exact final source is natively qualified.

Baseline Library evidence:
- https://github.com/melusi-k/ate-ios/actions/runs/44677739392/job/136093532936
- https://github.com/melusi-k/ate-ios/actions/runs/44673754703

## Hosted-base adaptation

This draft is based on main cce94c10a44406d3afe80bd8f71b18382d6bb8cb, not the held parallel-Compile packet or unqualified combined generation branch. The standalone exact-source receipt helper is included with CLI tests. Compile and all app/UI sources stay unchanged. The reviewed XcodeGen caller inventory rises from 26 to 28 because this split adds two native jobs. No parallel-Compile changes are included.
