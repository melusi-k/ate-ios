# Slice 14: checked standalone Keychain session persistence

Dormant RecipeShoppingSessionPersistence uses the actual Security Keychain service
and session account, with injectable Security calls for native fixtures. Initial
load and verifiedCurrent distinguish no item from locked/unreadable/malformed item.
No try?-nil signed-out conversion. Full AuthSession validation, no secret logs.

persist verifies the prior session has not changed, updates existing item IN PLACE,
adds only on errSecItemNotFound, and checks OSStatus. Signout verifies deletion status.
Both require exact bytes and decoded session readback before cache publication.
Update failure does not delete prior credentials. Readback failure can occur after
write, so error never claims rollback and final host must stay unmounted.

Six native tests UNRUN, all injected and never access real credentials: checked
refresh+signout, new item add, failed update retains prior item, false-success/readback
and concurrent replacement, locked/corrupt/nondatatype load refusal, delete/add errors.
207 Python PASS. Existing legacy Keychain.save/load unchanged.

Final host must first use verifiedCurrent throwing, bind coordinator persistence to
persist and every session writer/current-session source to THIS exact retained
state. AppStore's old setSession/Keychain.save is not an approved fallback in that
graph. This packet alone does not provide production wiring or native qualification.
