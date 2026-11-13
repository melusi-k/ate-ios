# #529 native minimized-tab expansion

Parent: a2fc00cb5415f2044545a130fa1f9e017d91c122 (diary materialization).
Hosted ancestor: 43589115e449e4fbb405f883e0a551a0be220999.

Final #529 NavigationHeaders fails while looking for the Journal TabBar button.
Its reverse Settings CollectionView swipe executes, but retained pixels still
show the upper Account & sync row below the header and the collapsed selected
Settings capsule at the bottom. The failure AX explicitly exposes Settings as
“Collapsed, Selected”. Journal does not exist in that minimized native TabBar.

Apple's current Tab bars HIG documents expansion by tapping a tab or scrolling
to the top of the view, not by an arbitrary partial reverse swipe:
https://developer.apple.com/design/human-interface-guidelines/tab-bars.md

The journey now taps the visible selected Settings capsule once to expand it.
It then keeps the single Journal navigation tap and every strict existence,
hittability, selection, arrival, one-header, logo and New entry assertion.
This replaces the ineffective reverse swipe. It does not retry Journal, disable
minimization, change the app, relax an assertion or extend a timeout.

Comparison: earlier 99731deb and 5725a43 runs pass this journey; the latest
43589115 fails with the explicit collapsed-state evidence above. This packet
claims a test-setup correction only, not a tested platform or product repair.

Verification: Python source guard/suite, Swift grammar parse and diff check.
Native replay and post-change screenshots remain required and unrun.
The menu, Cook completion and expandable-sheet allowance stalls are separate.
