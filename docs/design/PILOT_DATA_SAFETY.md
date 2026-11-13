# Pilot data-safety candidate (#498)

Status: Draft. Source preparation, not pilot acceptance.

Built on the reviewed shopping client candidate `7f1e447`; publication waits for Explore/shopping qualification and a confirmed destination base. No SyncCoordinator extraction, SQL execution or server deployment belongs to this slice.

## Reproduced source failure and boundary

`SyncMerge` deliberately merges opaque bytes. A newer malformed shopping payload replaces the local bytes; AppStore's later `compactMap` decode then drops the item. Recipe decoding is more permissive: a missing identity can generate a fresh UUID or a malformed title/ingredient field can become a default. Both paths can destroy a useful local copy.

The candidate preflights the full pulled receipt before account cleanup, merge or persistence. If any row is incompatible, it pauses the receipt, reports the count through the existing sync failure status and does not push. Local domains and existing receipt metadata stay intact. A first-account ownership marker may still be recorded before network I/O by the existing safety rule. No partial good-row commit or automatic bad-row overwrite is attempted. Unreadable rows remain on the server for diagnosis; they are not quarantined or deleted.

Checks include owner, kind, row/domain ID equality, nonnegative stamps, payload object shape, usable title/name, shopping decoding/quantity, typed recipe core arrays and bounded numeric conversion. Current unversioned rows and additive optional fields are accepted. Explicit schemaVersion/schema_version is not currently emitted; any explicit version pauses pending an adapter. This is a narrow compatibility preflight, not the post-pilot wire-version redesign. Tombstones still require identity/owner/kind but do not need payloads.

## Added source tests (not run natively here)

- Five fixture cases: legacy/minimal and current/additive recipes, additive shopping, malformed/identity/numeric/version failures with exact count, tombstones and foreign owner/kind, baseline opaque merge replacement sensitivity.
- Two AppStore lifecycle cases: mixed valid tombstone plus bad row cannot partially change either domain/metadata or push; offline/server503/cancelled pull preserves both local domains.
- One disk reopen case: recipe/shopping edits encoded in the actual SwiftData entities survive a fresh ModelContainer; verified cooking history reopens from an isolated defaults domain. It uses no backend. This is storage-component proof only, not actual app cold launch, Finish UI or process-kill proof.

The existing strict full AteTests lane selects these tests by target. No selectors/gates/timeouts weakened. Python execution is unrelated to native data-safety acceptance.

## Evidence still required

- Run all new native tests on the exact published candidate, alongside existing regression suites.
- Real iPhone, no network: cold launch existing saved data; edit recipe and shopping; cook and Finish through the actual UI; force quit; relaunch offline and check recipe/shopping/cook completion state. Keep before/after screenshots and exact build/device information. Do not substitute ordinary memory-only `-UITesting` startup.
- Interrupt an actual sync around merge/persistence and reopen the disk store; prove no partial local state. A thrown/cancelled pull is not process-kill evidence. Existing recipe and shopping persistence are separate operations; no crash-atomic multi-domain transaction is added by this slice.
- Push failure occurs after local merge in the current engine. This candidate does not claim that a failed upload restores the pre-pull snapshot; valid accepted remote state may already be local. Clarify that acceptance separately from preserving unsynced local edits. Inspect failure evidence before expanding this patch.
- Validate Shopping status and Settings error text visually; source assertions are not pixel proof.

No claim that #498, #72/#34 or pilot entry is complete. SQL/server race work is backlogged separately by the owner.
