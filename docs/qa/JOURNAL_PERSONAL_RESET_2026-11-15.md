# Journal local account/reset patch

Base: #539, `102d5cfd9d648c68ad7c98e5cf5758aaea5760f2`.

## Product scope

- Explicit sign-out clears Food Journal meals, reflections, drafts, cooked-reflection offers, local media and personal Journal backup/recovery files even when recipes are kept.
- Signing in as a different account clears the previous account's Journal before publishing the new credentials/identity. Same-account refresh and reauthentication preserve it.
- A hashed Journal owner marker survives token expiry, including when recipe sync never succeeded. It contains no email or raw account ID. This prevents account B from inheriting account A's Journal after expiry/relaunch.
- Settings Clear all now clears the Journal as well as the existing recipe scope. Confirmation and success copy name the Journal. Existing recipe/shopping/remote-account behavior is not broadened.
- Token expiry preserves Journal rows, meals, files and drafts. Calling expiry without a session does not invent an expiry banner.
- Goals remain preferences on Journal-only erase/sign-out-keep. The existing remove-all action retains verified goal deletion.

## Safety

The helper uses the actual bound Journal owner, not an unrelated singleton. Raw rows and meal payloads, orphan media and named backup directories use the existing verified reset components. It checks the bound writer validator for each component, fails closed on missing canonical bindings or owner mismatch, and never reports a partial erase as complete. Partial erasure still invalidates loaded rows and drafts. There is no rollback copy of personal bytes.

An old network sign-out cannot erase a newer account's records, including in the legacy graph. A local reset epoch blocks already-awaited sync snapshots and family commits from republishing over an explicit erase. Cached Insights work is invalidated too. The owner-change recipe pull no longer treats network pull success as proof that local switch publication succeeded.

The candidate runtime, family sync and #532 transition graph remain OFF. The later activated transition/quiescence composition and retained reset inventory still require reconciliation before activation. This patch is not an account-wide cloud deletion API and does not promise that a future activated cloud sync will forget remote records.

## Evidence and remaining gate

Local Python source contracts, exact inverse reconstruction/mutants, changed Swift grammar and diff checks are recorded with the packet. Inherited assertion hashes remain unchanged. The sole prior native expectation intentionally changed is the old sign-out-keep expectation that a private diary survives; goals still must survive. Original QA input, waits, allowances and timeout budgets are unchanged.

Native compilation, native XCTest, simulator/device execution and pixel inspection: **UNRUN here**. This is a candidate patch, not a confirmed device fix. Reviewer must inspect the new confirmation and empty/retained Journal screenshots before acceptance.

Required native selectors:

- `AteTests/JournalPersonalResetTests`
- `AteTests/JournalAccountActionBindingTests`
- `AteTests/DataArchiveTests`
- `AteTests/AppStoreWriterBoundaryTests`
- `AteTests/CookPlanAccountSafetyTests`
- `AteTests/InsightsRefreshOwnershipTests`
- `AteUITests/JournalPersonalResetUITests`

Full exact-head unit selection already includes the new unit class. The existing nutrition UI selection now includes the new UI class and requires each of its three pass receipts, retaining screenshots in the existing result bundle. No new runner or paid service is introduced.

New native cases cover actual Settings/sign-out/sign-in entry points, legacy and bound containers, structured meals and reflections, unrelated-container preservation, media/backups/drafts, same-account reauthentication, expiry without completed sync, nil-session expiry, stale sign-out, writer refusal and partial erase. UI cases use the real app routes/storage, not a timeline-state override.

No remote publish or merge was performed while producing this packet. Source PRs close only after the reviewer confirms the destination commit; branches kept.
