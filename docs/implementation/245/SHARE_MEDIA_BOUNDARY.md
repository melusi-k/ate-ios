# Activation slice: share-media original boundary (OFF)

Builds on20fb287b. The share extension previously created the Inbox directory and
wrote image bytes outside its queue's writer boundary. It now captures the boundary
before any NSItemProvider await, loads bytes only, and publishes image plus queue
reference inside that original retained boundary. A refusal creates no directory or
queue entry. Text/link queue publication also uses the same original boundary.

The app's consume-and-delete image helper now runs inside a retained writer effect;
it cannot delete a pending image outside the gate. Failed read/delete returns nil,
not fabricated bytes. A fixture directory parameter makes source preservation and
consumption testable without touching the real App Group.

No extension production gate is installed by this change. If startup leaves the
boundary at `.legacy`, it still provides no durable reset fence. Immutable shared
path resolution, extension entry-point admission and full orphan-media erasure remain
required. Existing queue UserDefaults persistence is not promoted to filesystem
transactional durability; a disk/defaults failure can leave orphan image bytes, which
the account-wide Inbox directory component must erase after quiescence.

One native test covers refused media publication (no directory/queue), one boundary
for image+metadata, original bytes, refused consume preserving source, and successful
consume removing source. Native compile/tests UNRUN.191 Python tests PASS. No
visual layout changed; share host/device execution remains unverified.
