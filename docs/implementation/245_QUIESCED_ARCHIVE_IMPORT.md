# Dormant quiesced archive import consumer

Parent: 02d700742d52d7b8bbcd522b271b0c013eae3ea5.
Activation stays OFF. No AppStore callback or production auth/RPC is installed.

The consumer decodes/validates the whole archive before migration/quiescence,
requires the owner's exact lifecycle gate/lease, refuses unreadable/nonempty
unarchived recipe associations, runs existing canonical migration barriers,
then cancels and drains the retained owner lifecycle.

Checked epoch revocation now returns the replacement UUID to its lifecycle.
Only a successfully quiesced lifecycle can use that private UUID once, under
the original gate's shared flock. It never captures a replacement writer lease.
Full session is checked again, and the caller's mandatory owner/receipt proof
runs under that held gate. Ordinary consumers still hold the revoked epoch.

The operation builds existing UnifiedArchiveImportBinding from the actual
retained journal/recipes/defaults/goals/media, using a nested no-flock lease.
It executes one existing journaled import, commits one durable generation,
then retires the recovery record. It does not nest an ordinary boundary or a
standalone session with another flock. Failure leaves recovery evidence for
startup; no implicit retry, reopening or graph publication occurs. Caller must
re-admit/rebuild the complete graph after any import attempt that quiesced it.
The result is the detailed existing archive result, not a truncated Settings
summary that would omit reflections.

Five required native methods cover malformed-file no-effect refusal,
drain-before-mutation/reflection import/exact generation/retirement/old-owner
closure, post-drain proof refusal, foreign lifecycle rejection and interrupted
import recovery without generation advance. Required union 70 to 75.

Python: 201 PASS. Five Swift grammar parses PASS (unchanged external flock
symbol declaration omitted for parser limitation). diff check PASS.
Native build/tests/pixels UNRUN. Root consumer inventory, real identity-proof
binding, post-import graph rebuild and generation-fenced sync remain pending.
