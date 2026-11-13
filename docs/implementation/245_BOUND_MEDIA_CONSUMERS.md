# Bound Journal media consumers (#245, step-4 preparation)

Based on the reviewed #530 tree c3fe799f. The existing Journal detail screen now
resolves photos through store.journalStore.boundMediaURL, the same owner that
loads its record. It no longer reads global JournalMedia when displaying an
injected owner. Legacy stores retain the same default directory and layout.

App Intent queries retain the exact JournalStore used for reading, and pass it
explicitly to entity construction. Returned IntentFile media points at that
store's directory. The create intent likewise uses the same store that saved its
record. No independently opened/global Journal is substituted after the read.

JournalArchiveCapture's no-override media path now defaults to its supplied
JournalStore.mediaDirectory rather than JournalStore.mediaDir. Explicit media
URL overrides retain their existing API behavior for owned archive participants
and tests. Missing media still fails visibly, never becomes a false empty set.

Three additive native tests cover owner-default archive bytes, Intent entity
bytes, and missing owner media refusal. A source guard checks detail, intents
and capture contain no static global media references. Required native union
retains its prior 47 methods and adds these three. 195 Python tests and Swift
grammar checks pass; native build/test and simulator/device pixels are UNRUN.
The detail screen layout is unchanged, but actual photo rendering must be
checked on the exact candidate before claiming visual acceptance.

This is a bounded consumer correction, not full canonical activation. No new
production owner is installed; archive/reset/startup/quiescence composition and
remaining app/extension consumer retirement still gate that switch. No backend
write/deploy, #523 workflow or anonymous-sign-in activation. #245 stays open.
