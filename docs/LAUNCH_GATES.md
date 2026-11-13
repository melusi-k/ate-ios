# Ate release gates: Pilot, then Launch

Approved by the owner on 10 November 2026. Two stages describe who the product is ready for. A build number identifies the software. Publishing a build is neither stage approval.

## Pilot: prove the cooking loop with a small invited group

Until TestFlight (#489) is enabled, Pilot means owner-device sideload builds only, and TestFlight-dependent evidence is N/A by the owner's 12 November 2026 decision.

### Entry criteria

- The agreed MVP scope is usable: import a recipe, review/save it, find it again, plan a cooking day, shop, cook and explicitly finish. Current MVP issues are #35, #72, #73 and #477, plus required import dependencies including #253. #89 is tracked at the Pilot gate. Each scoped criterion needs evidence or an explicit scope decision, not merely a closed issue.
- One installable candidate is identified by full commit SHA, build number and checksum. The owner checks the loop on his iPhone on that candidate: relaunch/persistence, offline saved-recipe use, reminders allowed/denied and real delivery, early exit without false completion, and Finish without falsely logging eaten food.
- Privacy/security basics for enabled pilot surfaces are checked: no exposed secrets or private-content leaks; truthful permissions; safe deletion/account boundaries where enabled; clear data-use information; safe failure/retry. Unneeded account/cloud/Health features stay off rather than inheriting an untested promise. Unified Food Journal activation is not a Pilot prerequisite and stays OFF.
- Relevant native checks ran. Data-safety checks #498 (offline durability, sync-failure preservation, payload-version fixtures) pass on the exact candidate. Actual failures, skips and device results are separate. Known runner stalls may be disclosed under existing owner policy, never relabelled passes. No unresolved data-loss, security or core-loop product defect.
- The owner explicitly approves that exact candidate and invited audience. Define the cohort, time window, learning questions and decision thresholds before inviting people.

### Exit criteria

Observe whether people can complete the loop and return to cook again. Record friction, repeat cooking and defects, then decide improve, stop or proceed. No success percentage or cohort size is invented by this policy.

## Launch: make the proven loop ready for general users

### Entry criteria

Pilot findings are addressed. Supported-device/OS coverage, production privacy/security, account/backup/deletion readiness for enabled features, reliable import/sharing and failure recovery, support/incident handling and distribution readiness have evidence. All launch-critical requirements and carried-forward Pilot safety requirements are bound to the candidate. The owner records an explicit go/no-go.

"Everything else" is not a gate. Optional features stay backlog unless they are part of the launch promise. Deferred features must not be exposed as working capabilities.

### Exit criteria

The approved candidate is distributed to its intended public audience, monitored, and has a working support/fix-forward path.

## Decision, evidence and history

- [#45](https://github.com/melusi-k/ate-ios/issues/45) is the single Pilot/Launch decision checklist.
- [#33](https://github.com/melusi-k/ate-ios/issues/33) is the exact-candidate evidence report feeding that decision. Automation may report missing evidence; it cannot approve a stage.
- [#30](https://github.com/melusi-k/ate-ios/issues/30) is engineering/evidence history, not a competing release milestone.
- Candidate records in [VERIFICATION_RECORDS](../VERIFICATION_RECORDS/) identify full SHA, version/build, channel, environment, device/test conditions, artifacts, limitations and explicit owner decision, following [PRODUCT_LIFECYCLE.md](../PRODUCT_LIFECYCLE.md).

## Acceptance inventory and issue triage

Stable IDs and definitions live in [MVP_CHECKLIST.md](MVP_CHECKLIST.md); per-ID evidence lives in [QA_MATRIX.md](QA_MATRIX.md). Historical scores in [MVP_SCORE.md](MVP_SCORE.md) are not current readiness.

| Inventory group | QA_MATRIX `Release gate` | Rows |
|---|---|---:|
| Pilot inventory, pending criterion-level scope reconciliation | `Pilot` | 97 |
| Launch inventory, plus carried-forward Pilot safety requirements | `Public launch` | 13 |
| Uncommitted backlog | `No committed release gate` | 71 |
| Total acceptance IDs | | 181 |

`Public launch` remains the compatibility inventory value for the Launch stage. The table records existing classification, not 97 newly mandatory Pilot criteria or a pass score. `scripts/check-ids.py` validates IDs, classification agreement and counts, not readiness. The readiness generator's 59 mapped evidence items are a different summary, not the stage denominator.

`gate:mvp` identifies work required to enter Pilot. Reconcile older `gate:pilot` and `gate:public-launch` rows individually into Pilot-required, Launch-required or uncommitted, recording what moved and why. Preserve acceptance IDs, historical results and dependencies. Do not silently move hard-to-test work out of scope or bulk-tick checkboxes. Until reconciliation is complete, report that gap explicitly; no aggregate score grants approval.

## Evidence rules

Report Pass, Failed, Blocked, Not run, Skipped and Partial separately with exact candidate SHA and artifacts. A pass needs all checks required for that criterion, including device checks where specified. Historical passes and source inclusion are not fresh candidate passes. A quarantine is a disposition, not a result: retain the actual failure/skip and linked issue. Missing evidence is not a product failure, but it cannot supply a pass.

A criterion becomes not applicable only through an explicit scope decision naming its ID and reason. Difficult, blocked or deferred is not the same as not applicable. No percentage threshold applies. Do not reinstate the former unapproved 90%/95%/100% scoring options.

## Naming and compatibility

User-facing names are **Pilot candidate - build N** and **Launch candidate - build N** until the owner approves the stage. `0.1.x` is a technical version line, not another stage. Build numbers remain numeric identifiers.

Keep existing immutable tags and links, including `build-415-TierA`. `TierA` remains a compatibility machine channel, displayed as Pilot candidate in release/readiness text. Do not rename it in archive metadata, diagnostics allowlists, Sentry guards, QA upload identities or promotion rules as a cosmetic change. `TierB`/`TierC` remain historical/compatibility tokens, not additional product stages.

`latest-build` means a published installable artifact, not an approved candidate. `latest-beta` retains its existing full-validation promotion requirements until an explicit separate workflow change is approved. The readiness generator retains its legacy hidden rolling key so #33 is updated, not duplicated. The generator's full-validation disposition describes evidence completeness; #45 owns the scoped stage decision.
