# Cook plan cancellation: test dismissal boundary

Branch-only test correction, 20 November 2026. Native UNRUN on this packet. No product persistence fix is claimed.

The native failure is consistent with a source-supported asynchronous dismissal race, but the native log does not prove that cause or the persistence outcome. This packet verifies the source mechanism only: CookPlanSheet.cancel() sets busy, cancels stored state, awaits notification cancellation, then calls dismiss(). The underlying recipe.plan button can exist before the sheet has dismissed, so waiting for that button's existence cannot prove dismissal.

After the real cancel tap, the test now requires the existing cookPlan.reminder form control to disappear within the same10s bound already used after Save. It then retains the original plan existence wait and tap. Before asserting that the cancellation button is absent, it requires the reminder control to reappear in the reopened form. This makes the absence assertion meaningful instead of allowing a transient period with no mounted form to satisfy it.

All original save, reminder-off, saved-date, reopen and cancelled-plan assertions and actions remain byte-carried. No runtime sources, workflows, selector lists, allowances or screenshots changed. No retry, arbitrary sleep, synthetic success or timeout increase. A failed dismissal, failed reopen or surviving plan remains a failed test. This does not prove persistence works across process restarts, or add that claim to the existing same-process reopen journey.

Python source guards prove exact inverse reconstruction of the original test and the action/boundary/check ordering. They are not Swift compilation or native proof. Reviewer must retain the original native failure evidence, run this exact method on the final head under existing budgets and inspect its retained saved-without-reminder screenshot plus final native outcome. Broader Nutrition qualification remains a separate native requirement. No remote publication, CI dispatch/rerun, merge or QA-result write is included.
