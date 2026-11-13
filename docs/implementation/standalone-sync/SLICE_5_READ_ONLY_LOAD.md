# Slice5: read-only pre-admission observer, no production mount

Hosted baseb670cf121c2f6ae111070b51269ab22d446c9879. Branch-only.
Adds explicit readOnlyPendingAdmission construction policy. Ordinary default is
unchanged. It loads decoded recipe/shopping values without normalize/dedupe,
stamping, saves, cook-session repairs, widget/intent relay install or publication.
The policy disables context autosave and prevents ordinary writer/sync entry.
It is immutable: a fully admitted graph must be constructed separately, not upgrade
this pre-admission observer by toggling a flag. It is never AppStore.current.

Raw undecodable rows remain untouched and MUST NOT be inferred empty from decoded
arrays. Legacy raw inventory/adoption is still pending. Public array setters may
alter this observer in memory but ordinary methods cannot persist them. Do not mount
this observer as the production graph or use it as a writer capability.

completeRecovery refuses the pending-admission/standalone route without resetting
metadata, exporting or claiming restoredFromSync. Legacy successful-sync flag now
requires actual .synced state instead of assuming any returned syncNow succeeded.
StoreRecovery.open remains unchanged and must still be gated/replaced in future
startup factory. No production call site or activation change.

One native on-disk fixture UNRUN: duplicate and undecodable raw rows, metadata,
blocked add/persist/sync, and completeRecovery retained as unverified without export.
207 Python tests PASS; diff-check PASS. Native compile/tests UNRUN.
Reviewer publishes only; source closures require destination confirmation; branches
kept. Food Journal OFF.

Reviewer v2 correction: public cook-session load refuses at entry, before legacy
decoder identity write. Observer constructs its own refusing DraftStore with reset
disabled, not DraftStore.shared. TimerCenter explicit read-only mode loads without
UI-test timer reset/persist and retains its refusing boundary. History/lifecycle
reset flags are policy-gated. Second native fixture seeds timer/cook/history/draft/
lifecycle bytes and supplies supported reset flags to constructor; all evidence
is asserted unchanged after collaborator calls. Native tests remain UNRUN.
