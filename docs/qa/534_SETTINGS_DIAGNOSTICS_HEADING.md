# Settings About diagnostics heading patch-forward

Base #534 exact head 8c326e4c9661625c6b162cf476f8ead6516449c3.
Account job 132912678537, run 43746654292 records
test32_MoreCollectionsToolsAbout failing after 158.899 seconds at
SettingsAboutGeometryReceipt.swift:21. At 154.38s the build-notes body exists;
at 154.81s the diagnostic heading StaticText query starts and cannot match.
Runtime reports computed Other versus requested StaticText. The literal
heading still exists and #534 did not rename it. Diagnostic interpolation of
heading.identifier resolves the missing query without an exists guard and
itself throws, stopping the original reveal loop. Concrete diagnostic failure
plus combined-child accessibility mismatch, not proof About was removed.

Earlier retained #534 head 775948c5 job 132845938693 stalled before completing
build-notes reveal. Current head reaches that heading/body before failing at
the next diagnostic heading. Different boundaries, not the same failure.
Current log alone does not settle remaining geometry.

Keep visible AI diagnostics heading outside the combined selectable details,
under an explicit contain parent. Model and last-generation details remain
combined with the same aiDiagnostics ID, text and selection; existing tests
checking Demo and milliseconds still query those details. Heading gets
aiDiagnosticsHeading; the original predicate is unchanged. Same stack spacing.
Remove only unsafe heading.identifier diagnostic interpolation; bounded
geometry receipts and screenshot remain. No added diagnostic reads/navigation.

CoverageUITests remains byte-identical: all viewport bounds, selectors, content
assertions, 25/50 scroll bounds, waits and allowances unchanged. Source tests
prove exact reversal of both changed files. No assertion/gate weakening, retry,
timeout, CI, auth or data change.

Native build/typecheck, XCTest and actual pixels for this patch UNRUN. Require
original test32_MoreCollectionsToolsAbout named pass and settings-about capture
on patched head. Confirm heading, nonempty diagnostic details, transparency
clearance and export. No native/visual acceptance claimed. Branch kept; source
closure requires reviewer-confirmed destination commit.
