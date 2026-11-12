# Shopping sync: receive cadence and conflict contract

Status: Draft

Owner requested live shopping sync on 12 November 2026 (#72/#34). Baseline main `628f444`. Existing `SupabaseSync`, per-item SyncRecord, AppStore metadata and account fences are retained, not replaced. Real cross-device sync was already present in source; what was absent was sustained visible receive and demonstrated conflict safety/device proof.

## Product boundary

Same signed-in account only. Shopping add/name/quantity/edit/tick/delete/clear use existing IDs, persistence, edit/undo validation, stamps and tombstones. Whole-item conflict resolution, not field-level merging, household sharing or a new account system. Recipe references do not create missing recipes. No Journal/Health data enters sync. Signed-out use stays local and is labelled that way.

While Shopping is visible and the scene active, sync on entry and every30 seconds after success. Failures back off60/120/240/300 seconds, reset after success; Sync now/pull-to-refresh remain available. The task stops on disappear/background/account change and is disabled during ordinary UI tests. No background delivery, server push, instantaneous receipt or phone-to-phone latency guarantee. Root's existing foreground sync and mutation debounce stay in place. One AppStore sync at a time; a request during network awaits queues a later sync instead of publishing overlapping snapshots. Local edits advance their own per-item clock monotonically, including rollback/same-ms cases.

## Conflict rules and server prerequisite

Higher whole-millisecond timestamp wins. Clock skew can still make one device dominate; this is not causal ordering. Equal timestamp takes the current server row as authority, including its deletion/live state. This can discard an equal-stamp offline edit or delete and is deliberate whole-item conflict resolution, not data merge. A server tombstone cannot be resurrected by equal/older edits. A strictly newer edit may replace an older tombstone. Recipe equal-stamp rules stay unchanged.

`supabase/review-candidates/shopping_monotonic_sync.sql` is deliberately OUTSIDE automatic migrations. It atomically preserves the existing shopping row when concurrent upserts submit an older/equal stamp, using the row lock in the update path. Existing RLS/grants remain, function search_path is empty, no owner bypass introduced. Do not deploy without review and staging. Without the server guard, a pull-before-push client cannot prevent a concurrent stale POST from overwriting newer remote state, so this client slice alone is NOT conflict-safe live-sync acceptance. A successful push is not proof its payload won; submitted shopping rows schedule one reconciliation, which cannot recursively schedule another just because it pushes. A fresh user/poll request can start a new bounded round. Existing synced timestamp means sync request completed, not proof every other phone received it.

## Required qualification, not yet run

- Review candidate SQL against current deployed schema/policies and dormant generation-reset work; no production activation or cloud erase is bundled.
- In staging, use authenticated roles and two independent connections. Race higher/lower and equal stamps in both commit orders; exercise tombstones, transaction rollback, RLS other-owner denial and unchanged recipe path. Retain exact schema/source and raw results before moving into migrations.
- Native units: equal-stamp convergence, server tombstones, losing offline delete, newer local queue, unchanged recipe ties, monotonic local stamps and backoff. Source tests are not execution evidence.
- Run AppStore overlap/account-change/local-edit-during-await cases with controlled transports, plus physical two-device add/edit/tick/delete/clear/offline/retry/sign-out checks. Poll cancellation and foreground resume need runtime evidence.
- Inspect Shopping status/refresh pixels at normal portrait/landscape. No new screenshots, native tests, authenticated staging or two-device acceptance is claimed by this candidate.

Source audit also found legacy/unbound `validatePostAwaitPublish` intentionally returns true before session equality checks. This slice checks the captured session explicitly at sync await continuations, including error handling, so an old-owner response cannot publish rows or expire a new session even while the canonical writer boundary is dormant. Controlled-transport native cases cover reentrant sync coalescing, owner change during pull and old-owner unauthorized response; they are not two-device or staging evidence.

Controlled transport also covers a local addition made during a suspended pull being retained and included in the resulting push. Native execution remains outstanding.

## Focused UI capture route

`ShoppingSyncCaptureUITests` selects four cases: signed-out local-only label in portrait and landscape, and signed-in status plus manual Sync now in both orientations. It uses the existing `-UITesting`, `-qaResetShopping`, `-qaResetServer`, MockAuth and MockSync startup and real Settings sign-in controls, not a production fixture or fallback. Manual refresh asserts the control is available, taps it and requires a successful status afterward; immediate mock completion does not require observing a transient spinner. This is UI evidence only, not a remote receipt or two-phone proof.

The existing account-cooking worker explicitly selects the suite, requires each named pass and retains its log, xcresult and exported screenshot attachments on every outcome. Existing selectors, gates and timeouts remain unchanged. New capture cases and actual pixels have not been run or inspected locally; reviewer CI and visual inspection remain required.
