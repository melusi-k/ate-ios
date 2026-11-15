# Journal detail action identity correction

Exact base #527 38d170fae6337199cc91bff3db69021c14d8f7e9. Reviewer reported
artifact 14009520310: 25/27 Journal UI methods passed; manual CRUD failed on
ambiguous Cancel, delete-failure retry failed on ambiguous journal.delete.confirm.
This packet is a source correction, not a native passing claim.

The delete alert was attached to the detail's top-level Group. Group is structural,
not a single concrete presentation owner; modifiers can be distributed across its
rendered children. The detail now has one full-size VStack presentation owner.
Delete continues to use the retained route ID and committed-save verification;
error detail retention, explicit retry, dismissal ordering and history checks are
unchanged. No deletion policy or storage code changes.

Editor Cancel/Save now have separate journal.edit.cancel/journal.edit.save IDs.
Delete confirm/cancel retain their distinct IDs. The manual CRUD test targets the
alert's exact cancel ID rather than global app.buttons["Cancel"], and all destructive
confirmation paths assert exactly one match before tapping. No firstMatch/boundBy
shortcut is used for these actions. Existing assertions for cancel preservation,
failed-save draft retention, successful edit/date preservation, committed deletion
and explicit retry all remain. Existing 10-second waits remain unchanged.

Static guards require one concrete detail owner, one alert registration and each
of the four action IDs exactly once in the detail source. The existing edit-retry
source guard still requires both Save taps, now under the exact new editor ID.
191 Python checks PASS after that selector-aware guard correction; diff check PASS.
Native build/UI/device/pixels UNRUN. Reviewer must rerun the same 27 methods and
inspect the actual hierarchy/screenshots before claiming these failures fixed.

#522 comparison: fetched exact head 41badff. Its detail still has generic Cancel
and no journal.delete.confirm ID, with the alert on its conditional List. Therefore
the exact #527 confirm-ID collision cannot be presumed to explain exit 65 there.
The account-cooking lane includes multiple distinct suites and a quarantined account
sync case. No failing #522 method/selector or full log supplied yet; exit 65 alone
is not a classification. No speculative #522 source changes included.

Rollback is this action-identity/container delta only. No user records, formats,
timeouts, workflow gates, merges or publication changed. Retain source branch.
