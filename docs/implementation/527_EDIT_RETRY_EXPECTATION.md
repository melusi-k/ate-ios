# #527 exact edit-retry expectation

Base: 9d9f367516dcea2f4ef79f7976a920b8d9af09c6.
Reported Journal run 43317963453, artifact 13997294333 fails at UI line224:
committed detail is "retained draftReflection failure <UUID>", while the test
expects a leading space. This is a real assertion failure, not a stall.

JournalStore.update already trims whitespace/newlines before saving, same as
manual creation. Its native test submits "  Retained edit draft  " and requires
"Retained edit draft" on the retained reader and independent committed reader.
Those two native methods passed in the supplied run. The UI editor insertion
position can be at the beginning, so typeText(" retained draft") produced a
leading space. Failed save must keep that exact raw draft; successful commit
must follow the store's established trim contract. Reusing one string for both
was a test-input/expectation mismatch, not evidence of a runtime data-loss bug.

The UI test now unwraps the raw retained draft, derives the expected committed
text using that existing contract and preserves strict equality at BOTH states.
It additionally rejects an empty/unchanged expected edit. History queries use
the same committed text, not an optional fallback. Failure injection, error,
editor-retention, explicit retry, dismissal and history checks stay intact.
No runtime file, native test, registry name or timeout changed.

The supplied run also shows original manual CRUD and confirmed delete PASSED.
That is comparative evidence against treating this run as a repeat of #526's
prior deletion failure. It is not full feature acceptance. #526 stable-delete
candidate is independent. This patch changes only the edit-failure/retry method
in the shared UI file, so retain all #526 delete additions when folding. Do not
replace that whole file. #527 edit-save transaction guards remain byte-identical.

Static/Python checks are not native, simulator, device or visual acceptance.
Fresh native rerun and screenshot inspection remain required. No activation.
