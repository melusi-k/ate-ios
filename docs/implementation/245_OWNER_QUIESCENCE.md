# Dormant owner consumer lifecycle

Base: reviewed union 7e06055700e6801dcb6723988168e8e584b06bb3.
Activation stays OFF. No production auth, RPC or consumer registration is installed.

The new retained lifecycle records the full admitted AuthSession and original
account UUID lease. Every validation and registration refuses a changed token,
logout or inactive graph. Quiescence first closes local admission, then revokes
only its original epoch, cancels every registered consumer and awaits every
actual drain. Failed invalidation/drain leaves the graph permanently closed;
it cannot claim completion or invalidate a newer graph. Successful quiescence
is idempotent. Caller must not publish a replacement until this returns.

AccountWriterGate adds original-lease-checked invalidation under the same flock.
The existing unconditional invalidation remains unchanged for existing callers.
LocalOwner accepts retained consumer validation, runs it at construction, owner
validation and every actual composed write. DiskResources and ProductionAdmission
forward it. Default compatibility preserves existing dormant callers, not a
claim of finished root composition: activation MUST supply lifecycle.validate
and register every async writer/media/sync/import consumer before starting it.
No generic abstraction can prove an omitted participant was registered.

Five required native methods exercise same-account token/logout refusal,
revoke-before-cancel and awaited drain, failed-drain all-participant handling,
stale graph refusal without revoking a replacement, and a real bound reflection
write refused after token change. Required native union grows 65 to 70.

Python discovery: 200 PASS. Six modified/new Swift grammar parses PASS, with
AccountWriterGate's unchanged external flock declaration omitted only for the
parser limitation. diff check PASS. Native build/tests/pixels UNRUN.
Remaining: archive-import consumer binding, complete consumer inventory/root
graph, actual auth transition wiring, generation-fenced sync and activation.
