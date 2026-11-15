# Settings Release Notes and per-release What's New

Branch-only slice for #74 Pilot. Base6f9fe56fc3fc3a8a544d79450006592a6316b375.
No publish/merge/dispatch/PR. Release-only scope supersedes the older wider local
Settings design: NO Roadmap/voting UI/models/hooks, remote refresh, Supabase or
network access. No gate/draft/qualification content changes. Existing technical
BuildNotes and About accessibility IDs preserved.

Settings Product > Release Notes opens bundled release list, applicable by build
and channel, newest minimumBuild first with stable ID tie-break. Detail contains
summary, Added/Improved/Fixed notes and optional View What's New. Each release has
its own ordered slides. Explicit Back/Next/Done/Close, page count, no autoplay or
launch popup. Zero-slide releases retain notes; missing images retain explanation.
Unreadable catalog shows unavailable instead of fabricated release history.

Curated seed describes only these release-note screens, not dormant/unlanded app
work. No invented release date. One release/two slides; model tests include zero,
one and multiple releases/slides and build/channel filtering. Beta label explicit.
Resource folder explicitly included in project.yml. No commit-feed ingestion.

Four required native unit methods ADDED; every prior named assertion retained.
One normal-size UI journey added to existing InsightsPresentationUITests suite:
Settings entry, list, detail, first/last, Back, Close, replay, Done, screenshots.
No waits/timeouts/retries/assertions weakened.209 Python PASS; diff-check PASS.
New Swift files grammar-checked only; NOT Swift compile/typecheck evidence.

UNVERIFIED: Xcode build/warnings, XCTest, actual UI pixels, one-slide/multi-release
native rendering, real offline launch, light/dark. Environment lacks Xcode/simulator.
Reviewer must capture and inspect actual exact-head iPhone normal-text UI before
acceptance. Warm 960x540 placeholder illustration pixels inspected and labelled;
it is NOT an app screenshot. Replace with synthetic native captures before shipping.
No production-ready or no-new-warning claim until those checks run.
