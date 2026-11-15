# Cook Finish and pushed-host accessory

Status: Draft candidate, native and updated pixels unverified.

Baseline: main `527dfb6`, Duo manual run `43255698417`, artifact `13962407467`. Actual pushed portrait screenshot inspected: the Original pap / Resume capsule covers the Finish label and most of its button. The paired modal portrait screenshot shows the complete Finish button. This is a real cook-loop problem, not an accessibility timeout.

Source: TimerBarInset keeps resume/timer chrome on pushed screens whenever cookTarget is nil. The pushed QA route sets path=.cook while a modal sets cookTarget, so the modal has no competing chrome. CookMode's safeAreaInset footer does not consume the outer floating chrome's measured band on this host. Hiding the tab bar alone was insufficient. The existing global bottomChromeMinY measurement already describes that band for pushed/root chrome.

Candidate: measure CookMode's unchanged host frame bottom and reserve the overlap band plus8points below the footer, using the existing chrome top measurement. Only pushed/nonroot Cook with no modal target uses this reserve; modal safe area remains unchanged. The actual Resume accessory is retained, not hidden to make the test pass. No hard-coded device or capsule height, no speculative root Add changes bundled.

Tests: two ordinary CookFinishAccessoryUITests launch the same pushed QA state in portrait/landscape, require the real resume accessory, a unique positive-height hittable Finish wholly above its frame, tap Finish and require actual completion UI. Explicit account-cooking worker selection, both named passes required, log/xcresult/screenshots retained. Existing test selections/gates/timeouts unchanged. The manual Duo modal/pushed captures gain the same hittability/clearance assertions without removing captures or changing opt-in policy.

185 Python tests pass, YAML/all36shellrunblocks parse, whitespace check passes. Native cases and updated actual pixels have NOT run here. Required next: exact-head iPhone18Pro qualification plus Duo rerun; inspect both orientations and modal comparison, verify Finish completes and no footer excessive spacing/crop. No success claim from source or Python. Root Add-over-content is a separate observed surface, not fixed by this Cook-only change.
