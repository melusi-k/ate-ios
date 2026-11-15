# #82 Journal root header candidate

Historical #82 says Tracker root; the current source exposes Journal as the root,
with Insights & Cooking History pushed from it. JournalListView already uses the
same ateRootNavigationChrome pattern as Shopping/Settings. No source divergence
was found that justifies a runtime patch before executing the focused test.

The existing named focused method
`CoverageUITests.testNavigationHeadersRemainStableOnShoppingAndSettings` is
extended in place with Journal. Its original Shopping/Settings assertions and
name remain unchanged, so existing named-method CI selection automatically picks
up the Journal checks, without a new job, budget or test-selection change.

Added normal/default-text initial Journal title/logo, single navigation-header,
first-content geometry and reachable New entry assertions, plus title/logo,
single-header and reachable New entry assertions after the same swipe-up pattern
used by the existing roots. keepAlways screenshots before and after are retained.
A swipe is attempted; this is not proof of how far content moved, full collapsed
large-title geometry, all orientations or a physical-device pass. Existing pattern
compares first content against header minY, not an invented hard-coded header
height. Review actual pixels before any #82 acceptance claim.

Historical pass comparison: original focused method passed29.864s on merged
#344 source740f81ad in Compile42610132681, per live #82/#37 issue evidence.
No new native run or broad rerun. The expanded method still requires execution
and pixel inspection on its exact candidate head. Other #82 findings stay separate: legal links follow the amended native-document
criterion (correct current documents, accessible rows, no Safari bounce; no share
action or share URL required), plus blank Settings row, notes freshness and
offline banner evidence.

Source-only packet, no issue closure, publication or runtime Journal activation.
