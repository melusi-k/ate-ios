# Dogfood build and distribution policy

## Automatic flow

Every push to `main` starts two independent workflows/jobs:

1. **Fast engineering IPA** — the existing Build IPA workflow builds, verifies, checksums and publishes an immutable `build-N` artifact plus the rolling `latest-build` release. This remains available even if qualification fails; it is not, by itself, a dogfood approval.
2. **Dogfood qualification** — runs against the exact same Git commit SHA and requires:
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

- [ ] Every main push runs unit tests and the seven required critical flows against the exact pushed SHA.
- [ ] Failure of a required check fails qualification while leaving the fast IPA/release artifact path independent.
- [ ] The Settings/account-sync quarantine remains visible as **QUARANTINED / NOT A QUALIFICATION PASS**, with logs and xcresult retained.
- [ ] Job summary includes commit SHA, required-check status and quarantine status.
- [ ] README and QA policy agree with the actual workflow triggers and gates.
- [ ] Before TestFlight is enabled: validate App Store signing/profile mapping, API-key authentication, archive export, upload response and internal tester availability.
- [ ] After Apple access is available: record a real TestFlight upload/build processing result for the exact source SHA. Until then, TestFlight is blocked, not passed.

See [issue #78](https://github.com/melusi-k/ate-ios/issues/78) for CI reliability, quarantine and workflow-policy follow-ups.
