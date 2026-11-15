# Repeated native alert count2: evidence only

Base ab1e89050b6a38e0d3a134bf5789fe1afdeedd71. Run43430000088 still
counts two native confirm/cancel matches, before either action executes. Complete
raw Journal log has no failed-alert hierarchy at either count failure. Earlier
SwiftUI-to-native replacement did not fix it; do not repeat that hypothesis as fact.

This patch adds kept screenshot plus alert and full app debugDescription before
each existing strict count assertion in CRUD and failure/retry methods. All
assertion/count/selector/action/wait/timeout lines retained. No runtime change,
firstMatch, fallback, retry, AX hiding, workflow change or waiver. Evidence must
be inspected before choosing another runtime patch. Current code defines each
identifier once on its native UIAlertAction; no duplicate container identifier
or second SwiftUI delete alert remains in source. Native framework AX projection
is still a hypothesis, not proof of which node should change.

192PythonPASS, Swift grammar and diff-checkPASS. Native evidence capture is
UNVERIFIED until exact-head CI. Not a fix or native pass. Existing strict tests
are expected to stay red if the repeated count2 persists. No push/dispatch/merge.
