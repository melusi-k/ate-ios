# Fenced staged recipe/shopping cycle, current532

Increment on58f9f9ea. Uses existing FoodJournalGenerationSync owner, no parallel
host or transport. One busy interval covers snapshot, proposal, original-generation
upload and synchronous commit. Local recipe/shopping/metadata value must still
match before upload and after upload. Same-owner token, receipt/generation,
original lease and cancellation are checked before publication. Existing pending
pull capture refuses the new cycle, and new pull/push refuses during it. No retry.

Actual commit is an explicit closure that must compare expected image under the
same held graph boundary, durably journal it, then publish memory. No production
host call is installed yet. Reason: existing journal projects its metadata authority
on startup, so ALL ordinary recipe/shopping metadata writes must join it before
host replay can be installed. Wiring only sync would roll back later local stamps.
Current532 already has producer/host bindings; do not copy older singleton wiring.

Production AppStore loop unchanged in this packet. Build441 upload remains OPEN.
Next installation must include ordinary write journal routing, strict startup
replay before load, personal redo bytes in both unopened/retained reset inventories,
then AppStore staged path and host injection. No feature activation or backend write.
Native SDK/device tests UNRUN. Added required native cases cover success, local
edits across both awaits, upload/commit errors, same-owner token replacement,
concurrency/pending capture, cancellation ignoring transport, malformed remote rows.
