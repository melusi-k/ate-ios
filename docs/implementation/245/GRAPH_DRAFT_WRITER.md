# Activation slice: graph-retained draft writer (OFF)

Builds on6af6cd35. AppStore now owns its draft service: legacy graph keeps the existing
shared service, admitted graph constructs one against actual runtime defaults and
its immutable writer boundary BEFORE load. AddRecipeSheet and AppStore clear/save
routes use that retained service rather than the process-global DraftStore.shared.
An old completion holding the old store cannot switch to a replacement draft writer.

Draft begin/end/save/clear enter the boundary. Save encodes the card before retiring
pending input and keeps pending+card update in one effect. Boolean acceptance lets
normal completion/repair surface a refused save instead of claiming durable draft
success. Deliberately disabled draft persistence in hermetic UI tests accepts a no-op,
as before; it is not a disk-write claim. Clear/end still prove the boundary.

Two native tests add original-writer refusal across replacement, preserved pending
bytes and the graph's retained service/epoch. Existing draft tests/assertions remain.
Native compile/tests UNRUN.191 Python PASS. No layout changed, but AddRecipeSheet
completion behavior needs native UI regression qualification before shipping.

Host still must unmount old UI and stop/join generators; in-memory draft assignment
can precede a failed persistence result, so no rollback/no-change claim is made.
UserDefaults does not become transactional/durably fsynced through this seam. Full
reset inventory includes draft keys after quiescence. No route activation/deployment.
