# Dogfood build and distribution policy

## Automatic flow

Pull requests targeting `main` run Dogfood qualification before merge. Every push to `main` starts the fast IPA workflow; Dogfood Qualification runs for pull requests and can be started manually with `workflow_dispatch` for explicit post-merge or release investigations:

1. **Fast engineering IPA** — the existing Build IPA workflow builds, verifies, checksums and publishes an immutable `build-N[-channel]` engineering artifact; main builds may then advance the rolling `latest-build` release. This remains available even if qualification fails; it is not, by itself, a dogfood approval.
2. **Dogfood qualification** — `.github/workflows/dogfood-qualification.yml` runs against the exact PR or main commit SHA and requires:
   - the complete `AteTests` unit-test suite;
   - seven stable critical flows: add from URL, add from photo, generate/edit, save, share, open shared recipe, and timers.
   - a retained diagnostics run of `testQA7_SyncAccount`, tracked by [issue #76](https://github.com/melusi-k/ate-ios/issues/76). That test is explicitly **QUARANTINED / NOT A QUALIFICATION PASS** while the Done-button selector issue is unresolved. Its result is recorded but does not change qualification.

A failed required unit or critical-flow check fails the qualification job, not the independent fast IPA build. A green qualification job means only the named unit/critical-flow checks passed; it does not imply that every UI shard, backend E2E, physical-device acceptance or App Store/TestFlight distribution passed.

## TestFlight boundary

TestFlight distribution must use an App Store Connect-compatible signed archive/export and authenticated upload. The existing unsigned/ad-hoc/development sideload IPA is **not** a TestFlight upload artifact.

The following Apple-side configuration is still required before enabling and verifying the upload stage:

- Paid Apple Developer Program membership and an App Store Connect app record with the correct bundle ID.
- App Store distribution certificate/private key and App Store provisioning profiles for the app and every embedded extension that requires one (widgets, share, watch/watch widgets, and App Clip if included).
- An App Store Connect API key, Key ID and Issuer ID stored as GitHub Actions secrets.
- An internal TestFlight tester group, with the desired testers added and the app's distribution settings completed.

Do not reuse `BUILD_PROVISION_PROFILE_BASE64` or assume its current development/ad-hoc/enterprise export method is valid for TestFlight. Keep TestFlight export/upload in a distinct, explicitly gated stage using `app-store-connect` export options. If the Apple configuration is missing, report TestFlight as **BLOCKED — Apple signing/App Store Connect configuration unavailable**; never report an upload as successful.

## Acceptance evidence

- [ ] Every pull request targeting `main` runs unit tests and the seven required critical flows against the exact PR SHA.
- [ ] A manual post-merge qualification run can validate an exact main SHA when explicitly requested.
- [ ] Failure of a required check fails qualification while leaving the fast IPA/release artifact path independent.
- [ ] The Settings/account-sync quarantine remains visible as **QUARANTINED / NOT A QUALIFICATION PASS**, with logs and xcresult retained.
- [ ] Job summary includes commit SHA, required-check status and quarantine status.
- [ ] README and QA policy agree with the actual workflow triggers and gates.
- [ ] Before TestFlight is enabled: validate App Store signing/profile mapping, API-key authentication, archive export, upload response and internal tester availability.
- [ ] After Apple access is available: record a real TestFlight upload/build processing result for the exact source SHA. Until then, TestFlight is blocked, not passed.

See [issue #78](https://github.com/melusi-k/ate-ios/issues/78) for CI reliability, quarantine and workflow-policy follow-ups.

## Engineering artifact publication safety

Build IPA publishes an immutable per-build prerelease with exactly the IPA and its
SHA-256 file. The tag binds to the full workflow source commit. A retry may reuse
that release only when source, release state, asset inventory and downloaded bytes
match the current build. A tag/byte conflict, permission/network failure or failed
published-IPA smoke check fails publication without deleting immutable history.
A retained failed-smoke artifact is diagnostic evidence, not an approved install.

Only after the published IPA passes checksum and existing structural/content checks
may a main-branch build advance `latest-build`. A lower build number, source no longer at current main, or same-source
replay leaves the alias alone. An unknown current alias or same-number/different-source
conflict fails closed. Feature-branch dispatches can publish immutable artifacts but
cannot move this main engineering alias. Only the short publication job is serialized across refs with `queue: max`
(up to 100 pending publications). Builds and all test jobs remain parallel.
Start order is not guaranteed and excess runs can be canceled, so this is not a
promise that every push will get its own release.

The rolling alias is a convenience, not permanent history or qualification evidence.
This check is a publication-time snapshot, not a lock on future main pushes or
manual administrator changes. Replacing it is not atomic: an interruption can leave it missing. Use the verified
immutable build tag to recover; never delete or retag immutable builds to repair it.
The separate `latest-beta` path, production promotion, signing/distribution policy
and release-notes baseline selection are unchanged by this safety correction.
Full focused/UI/backend gates and on-device acceptance remain required as documented;
fast engineering publication does not waive any of them.

### Exact handoff and qualification boundary

The build job prepares a four-file handoff (IPA, checksum, notes, source/run manifest)
at the former publication point, before the unchanged final focused gate. Its exact
upload artifact ID and manifest SHA-256 become job outputs. A separate macOS job
checks out the same commit, downloads only that artifact ID from this run, rejects
transport digest errors, checks the manifest against the source-job output, and
verifies source SHA/ref/run/attempt, inventory and every file checksum before any
release mutation. It never rebuilds or signs a replacement. Missing outputs or a
failed handoff block publication. A failed focused gate after preparation remains
failed while engineering publication can proceed, as before. Any earlier blocking
build/smoke failure prevents preparation and therefore publication. Cancellation
suppresses the new publication job rather than initiating a release afterwards.

Beta promotion now additionally needs successful engineering publication; it still
needs successful original build/focused, all UI shard and backend jobs. No test
outcome is ignored or changed. This separation adds one short macOS runner allocation
and one exact artifact upload/download per build, but does not serialize builds/tests
or repeat them. Rolling alias bytes and checksum are downloaded and compared after
replacement; an alias failure still leaves the verified immutable build available.
