# Slice 9: dormant known-owner legacy adoption

Branch-only, not mounted or activated. Food Journal stays OFF. Parent gate remains:
source PRs close only after reviewer confirms destination commit; branches kept.

RecipeShoppingLegacyAdmission captures the complete raw recipe/shopping image and
exact legacy sync metadata under the existing concrete writer gate/lease. It requires
an explicit matching metadata owner and strict decoded IDs/stamps. Nil/foreign owner,
missing metadata, corrupt records or duplicates are refused, never treated as empty.

Before any first generation receipt is written it fetches a strict live snapshot,
requires generation zero, rechecks the exact session/gate and compares a second raw
capture. Advanced generation, lost transport, account change and local edits refuse
without stamp, delete or upload. This is not permission to adopt advanced local data.

Preservation retains raw record bytes, positions, createdAt and exact metadata bytes
including stamps/tombstones. It is checksummed, exclusive-temp-written, fsynced and
fullfsynced, renamed, parent-fsynced and read back before receipt.save. Exact complete
prior evidence can be reused only after durability checks; corrupt/conflicting or
partial evidence is retained and blocks adoption. Symlink/noncanonical directories
and nonregular evidence refuse. A reset component covers all personal preservation
bytes under its dedicated directory, with reset gate supplied by final composition.

Six native tests UNRUN: exact image/metadata preservation before receipt and no puts;
unknown/foreign/advanced refusal; changed raw inventory; corrupt temp retention;
changed session across await; existing receipt refusal before read/network. These
are injected raw-capture fixtures with real gate/receipt/preservation files, not
production StoreRecovery or account-wide reset qualification.207 Python PASS.

Open composition requirements: strict read-only pre-admission ModelContainer open
and raw capture, final reset inventory, owner remount and shared writer rebinding.
This helper cannot silently create a receipt for an empty install with unknown owner.
