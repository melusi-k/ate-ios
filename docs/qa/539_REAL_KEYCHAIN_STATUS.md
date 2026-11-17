# #539: actual Keychain status, without bypassing durability

Base832042107e510ec75fa7be627d240982a809f2db, https://github.com/melusi-k/ate-ios/pull/539.
Account failure evidence https://github.com/melusi-k/ate-ios/actions/runs/43885266110/job/133361685416?pr=539.
The earlier memory-credential setup packet was REJECTED and is NOT part of this branch. All original UI launches, assertions, timeouts, retries and real Keychain access remain unchanged.

## What is established

All four initial sign-ins (Shopping landscape/portrait, SettingsSync, AccountSwitch) show authError exactly matching AppStore.sessionWriteFailureMessage. #539's new checked credential write can refuse session publication, whereas main4aa5 and #548's old save published session before an unchecked delete/add. These failures are real, not waived as CI-only. None has reached the later sync or account-switch assertions. The code which skips dormant family sync during UITesting is not an explanation for failed session persistence.

Raw Security status and effective signed entitlements were NOT retained. The precise cause is UNPROVEN. The error can come from a refused setSession, not exclusively one proven SecItem return. No query fix, entitlement repair or simulator exclusion is justified yet.

## Old/new Security comparison

Old save: class genericPassword + service com.melusik.ate.auth + fixed account; delete first, then add valueData and AfterFirstUnlock accessibility; both statuses ignored. New save: same lookup, update with valueData and AfterFirstUnlock; only item-not-found goes to add, using the same add attributes as before. Any other update error or any add error returns false. Delete never runs as a fallback, so old valid credentials are not deliberately destroyed on write refusal. Load uses the same class/service/account plus returnData and matchLimitOne.

No explicit access group, synchronizable flag, access-control object or return-result key is added to update. Apple permits real item attributes in attributesToUpdate and prohibits return-result keys in the query; no such keys are present. No evidence currently singles out the accessibility setting or query shape as invalid. Both old and new add paths use AfterFirstUnlock.

All application Keychain uses are centralized in this helper: session credentials and PKCE verifier save/load/delete. PKCE save still ignores its Bool, so a passing magic-link request is not proof that PKCE durability succeeded. MockAuth UI journeys do not exercise the live PKCE flow. Other passing Account runs on #548/#549 used unchecked save behavior, not a separate proven working Security implementation. Main comparison is source-only; retained passing main auth execution evidence was not supplied.

## Sideloaded iPhone risk

The checked write is not simulator-only. If the actual re-signed iPhone app returns a Security write error, #539 correctly refuses sign-in rather than displaying a session it cannot durably save. That means the sideloaded pilot is NOT qualified for sign-in yet. Conversely, an unsigned simulator failure does not establish that a correctly signed device install fails.

Repository entitlements contain App Groups and HealthKit (signed variant adds associated domains), not explicit keychain-access-groups. Apple documents that a signed app's application-identifier supplies its private default access group; omitting a sharing entitlement is therefore not itself a defect. This code omits kSecAttrAccessGroup and uses that default. Adding a hard-coded team/access group without inspecting the final re-signed app could introduce a new mismatch or isolate earlier credentials.

The build workflow has both signed archive/export and unsigned sideload routes. The latter embeds ad-hoc entitlements for a later Sideloadly/AltStore signing step. Repository plist or pre-re-sign IPA metadata does not establish the effective identity and entitlement set on Melusi's phone. Before claiming a device repair, inspect the effective re-signed app's codesign entitlements/provisioning identity and actual operation status. A change in signing identity can also change which private group is accessible; do not delete inaccessible previous credentials speculatively. No device/profile inspection was possible here.

## Diagnostic patch, not a cure

Wrap the existing LIVE read/delete/update/add calls. Each runs exactly once, returns unchanged OSStatus and contributes fixed operation+numeric status to a24-entry process-local lock-protected trace. A system log line contains only operation and status, not queries, values, tokens, identifiers, group names, entitlement contents, raw errors or credential lengths. No persistent trace file, network upload, entitlement fetch, retry or fallback. Existing fail-closed control flow and typed diagnostic history remain unchanged.

For the existing sessionWriteFailureMessage only, authError retains its original visible text/identifier and exposes the bounded numeric trace as accessibilityValue. The failure hierarchy can now contain e.g. update:<actual code>,add:<actual code>. These are format examples, NOT observed statuses. This avoids waiting for a late container scrape to discover which real call refused. The trace is context, not proof that the last call caused every higher-level error; if no Security write appears, inspect setSession's earlier branches instead.

On the next authorized run, retain the original failed accountEmail assertion and its inner hierarchy plus system/app log. The status should separate update refusal from item-not-found followed by add refusal, read failure or delete refusal. Consult the named OSStatus before proposing changes: missing entitlement calls for effective-signature comparison; param calls for exact safe key/attribute inspection; interaction/auth errors need device unlock/access checks. Do not change code merely because one of these categories is plausible.

The trace resets on process exit and can roll over after24operations. Capture the hierarchy before termination. It is not a durable device support export. System-log availability and AX value collection must still be verified in native execution. No failure-time PNG exists in the original supplied evidence, and no updated UI/accessibility pixels or value were executed here. Visual/native verification is UNRUN, not passed.

323PythonPASS, exact original Auth.swift/AuthSheet inverse audits preserved, added-source identities pinned, diff checkPASS. New native diagnostic tests cover success/item-not-found/missing-entitlement/interaction/param/auth status forwarding, exactly-once calls, ring bound, ordering and fresh-instance isolation. Native compile/typecheck/XCTest/device UNRUN. Existing checked-write/native-refusal tests are byte-unchanged. No UI test changes, mock setup, workflow mutation, entitlement change, delete-first restoration, native rerun, remote publication, merge or production write.

## Apple sources

Read in this investigation:
- https://developer.apple.com/documentation/security/secitemupdate(_:_:).md
- https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps.md
- https://developer.apple.com/documentation/security/errsecmissingentitlement.md

Keep #539 held until Reviewer confirms destination commit and real results. Source PRs close only after reviewer confirms destination commit; branches kept.
