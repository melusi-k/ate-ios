# Native release notes launch follow-up (#74 Pilot P1)

Base a5c884f713eefefad52f25b659cbe43cd2cdceea. Branch only. No Notelet
adoption, dependencies, copied code, vendoring or license obligation. Feature ON.
Existing Settings history and native paged tour are reused, not duplicated.

The previous no-launch-popup limit in RELEASE_NOTES_LOCAL.md is superseded.
CFBundleShortVersionString (AppConfig.appVersion) selects an exact bundled version;
no matching entry, malformed catalog, future build or zero slides means no popup.
Build increments inside one marketing version do not repeat the launch tour.
Local defaults store seen versions only on sheet dismissal (Done, Close or swipe
dismiss), including replay dismissal. The dismissal requests StoreKit review;
StoreKit decides whether to display a prompt. A call is not proof a prompt appeared.
No remote loading/media, analytics, Supabase or diagnostics added.

Launch host defers while onboarding/recovery/auth/Cook/import/quick-add or an
incoming launch URL owns the surface. Active-scene changes re-evaluate eligibility.
Existing hermetic UI journeys bypass auto-presentation; the dedicated test opts
into the real launch path with an isolated defaults suite retained over relaunch.

Catalog is Codable for later remote loading, not current network permission.
Only factual current marketing version0.1.0 is seeded (project.yml);0.1.x is the
technical line. Pilot candidate is not Pilot approval. No invented historic
versions or dates. Entry opens with main feature, then What to Test / How to Test;
MVP/Pilot/Launch terminology does not create gates or change readiness. Historical
catalog enrichment is follow-up when grounded release records exist. Existing
placeholder illustration stays explicitly labelled, never passed as an app capture.

Evidence: added unit tests for unseen/current-version selection, dismissal-state
persistence using a fresh defaults instance, missing/future/empty-slide behavior,
Codable roundtrip and offline bundled seed. Added normal-text UI journey for real
swipe paging, dismissal, relaunch/no auto-show and replayable Settings history.
Existing tests/assertions are retained. Source contracts check no network path.

UNRUN: Xcode compile/typecheck, XCTest and simulator normal-text screenshots:
this environment has no Xcode or iOS simulator. No synthetic mock is substituted
for actual app pixels. Native test source exists but is not execution evidence.
Airplane-mode device launch, onboarding/presentation collision checks, StoreKit
request behavior and page/label fit require exact-head native/device qualification.
Run ProductUpdatesLaunchTests, ProductUpdatesLaunchUITests and the existing
ProductUpdatesTests / InsightsPresentationUITests release-notes journey. No lane,
assertion, timing allowance or diagnostics changes in this slice. Merge held.


## Source-review follow-up

Real onOpenURL and browsing activity already converge on AppStore.handle(url:).
That shared handler now latches session-local incoming-work priority, queues URLs
if a launch tour is onscreen, dismisses the tour without marking it seen or asking
for review, then routes the queue from sheet onDismiss. Cold callbacks suppress
launch selection; warm callbacks cancel a presented tour before routing. Onboarding
completion retains the incoming-work latch. No sleep or raised timeout involved.
The launch-argument URL alone is not used as evidence of real-link delivery.

Dedicated product-updates-ui.yml runs on the existing xcode-27 label,60minute job,
exact-head checkout and unchanged240/480second per-test caps. It selects all old
catalog tests, new launch/state tests, actual cold/warm custom URL UI tests using
XCUIApplication.open, onboarding handoff and the previous Settings tour journey.
Every selected named pass is required; zero/missing execution is not acceptance.
Screenshots and native result bundle retained on failures too. No dispatch run.

UNRUN remains: all new native code/typecheck/UI acceptance, cold and warm actual
URL lifecycle and onboarding handoff screenshots. Additional screenshot/hierarchy
diagnostics are not part of this feature. Existing workflows/assertions/caps stay
unchanged; this adds a dedicated qualification route, not broader CI time limits.
