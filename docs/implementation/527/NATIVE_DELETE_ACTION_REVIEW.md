# #527 native delete action ownership candidate

Base: 5725a43bee94a5a57e36869c8ab113827a9d266a.

## Evidence and limits

Compile run 43372485083, job 131711328613, failed both strict Journal delete tests on that exact head. Line 286 found 2 cancel buttons instead of 1; line 330 found 2 confirm buttons instead of 1. That head already had a stable VStack and distinct action IDs. Repeating either fix does not address this evidence.

https://github.com/melusi-k/ate-ios/actions/runs/43372485083/job/131711328613

The raw log was inspected. It does not include the alert AX tree. The listed debug description attachment is for journal.entry. Therefore the exact duplicated wrapper and runtime root cause remain unproved. Native controller/action ownership is a bounded replacement candidate, not a claim that static checks prove runtime uniqueness.

## Source change

- The stable detail container embeds one transparent, zero-size controller host instead of SwiftUI's delete .alert projection.
- One native UIAlertController owns exactly one Cancel action and one destructive Delete action. The public UIAlertAction.accessibilityIdentifier property is used directly. No private KVC, hierarchy hiding or chosen first match.
- Same alert title, message, system presentation and action roles. Each explicit open constructs fresh native actions. Multiple view updates cannot allocate a second active alert.
- Dismissal completes before running the selected handler. Presentation identity is retained through that completion. A per-presentation UUID must still be valid and marked for delete before its selected handler can run; completion consumes it before calling out. False transition, cancel, detach and retirement revoke the token. Old/duplicate actions or completions cannot act on a later presentation. No polling, async retry, timeout change or global topmost-controller lookup.
- Existing deleteConfirmedEntry, storage verification, error retention, explicit retry, detail dismissal and parent revision ordering are unchanged.
- Both native UI test methods, their exact count assertions and every wait/timeout are byte-for-byte unchanged.

Public API evidence inspected:
https://raw.githubusercontent.com/xybp888/iOS-SDKs/master/iPhoneOS18.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIAccessibilityIdentification.h

This SDK header declares UIAlertAction's conformance to UIAccessibilityIdentification; the property is not reached through private selectors.

## Checks and remaining gates

- 192 Python tests PASS, including seven focused Journal static checks. These are source contracts, not runtime proof.
- Seven new native unit tests: two check exact action counts, IDs, copy, enabled state, roles and fresh actions across constructions; five deterministic Host tests inject presentation/dismissal drivers to check updates/appearance during dismissal, exactly-once completion, false/true transition, retirement, detach/reattach and cancel/reopen. All seven are UNRUN here. The injected driver is the same Host code path with UIKit animations replaced, not an alternate state-machine implementation.
- Native build, presenter lifecycle, accessibility tree uniqueness and actual alert pixels: UNRUN here. This environment cannot execute iOS UIKit.
- Reviewer must qualify the exact candidate head: native compile, all seven new unit tests, both unchanged CRUD/delete-failure UI tests, one count for each action at every open, cancel retains reflection, first failed delete retains detail/error, explicit retry removes entry and returns history. Verify no duplicate presentation or missing alert after cancellation/reopen. Inspect native alert pixels at normal text on iPhone 18 Pro.
- If native uniqueness/presentation fails, stop and capture the actual alert tree. Do not weaken assertions, add retries, increase timeouts or hide descendants to force a pass.

Branch-only packet. Reviewer publishes/merges. Source PRs close only after reviewer confirms destination commit; branches kept.

## Lifecycle review revision

Reviewer returned CHANGES on 33185291: active identity had been cleared before dismissal and the callback lacked a cancellable operation token. This revision retains identity until matching completion, checks valid/pending token plus attached/requested/not-retired state, consumes before callback, and invalidates on false/cancel/detach/retire. No native claim is upgraded by adding unrun tests.

Original failure pixels were later inspected: one Cancel and one Delete are visible in each original alert, despite exact-count2 AX failure. They support projection mismatch but do not identify the duplicated AX node type. Native candidate pixels remain UNRUN.
