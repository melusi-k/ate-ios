# Cook-plan notification removal: responsiveness hypothesis

Exact base #497 262313e046489576594245eca7181823754549a1.
Native UNRUN. Branch-only. No waiver, publication, merge or closure.

Nutrition job 132752986896 exceeded its existing four-minute allowance in
CookPlan.testSavedRecipePlanWithoutReminderCanBeReopenedAndCancelled.
The supplied 10:43:08..13 UTC sample has 399/399 target Main-thread samples
inside SystemCookPlanNotificationClient.remove at line 42, through
removePendingNotificationRequests and a synchronous barrier/XPC call.
A later sample is back in the runloop. This is evidence of a Main-thread
wait during that sample, not proof of permanent deadlock or the entire
four-minute duration's cause. The mid-test screenshot shows Reminder OFF
and a saved plan, not final cancellation proof. Other Nutrition cases and
1170 unit tests passed on the original run; those are not patch qualification.

The @MainActor client's async remove method previously called synchronous
OS removal directly. Async did not change the executor. This patch moves
only synchronous pending/delivered removal into an awaited utility-queue
operation. Empty ID arrays make no OS request. removeAllDelivered retains
its existing prefix filtering and uses the same awaited boundary.

The entire CookPlanNotifications intent/verification owner is unchanged.
OFF saves still remove obsolete reminders, including an ON add suspended
in the OS. Skipping cleanup simply because the new plan is OFF would lose
that guarantee. No fire-and-forget cleanup, early success, deadline, retry,
new timeout or unverified-success path is added. Removal can still wait on
the OS; now it suspends its caller rather than blocking Main. Pending-ID
verification still follows removal. Existing failure reporting remains.

Two added native tests assert that an injected blocked synchronous removal
runs off Main, Main remains responsive while it is blocked, requested IDs
are preserved, completion does not return early, and empty IDs do not
contact the system. All original native tests are byte-preserved. Source
contracts verify the unchanged complete intent owner and original test file
with exact SHA256, without baseline git objects at runtime.

The native compiler, notification service, saved-plan reopening/cancelling,
reminder ordering, pixels and responsiveness remain unverified until the
Reviewer runs the original gate on the destination. Swift grammar and
Python/source guards are not substitutes. Focus evidence must be reviewed
against BOTH its actual anchor and destination after folding.

Source PRs close only after Reviewer confirms destination commit; branches kept.
