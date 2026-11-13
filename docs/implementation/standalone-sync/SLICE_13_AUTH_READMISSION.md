# Slice 13: bounded 401 refresh and fresh admission

Dormant coordinator extends the existing lifecycle slice. Explicit dependency:
merged EXACT hosted RPC-error branch9ee47a6b90ed3aa85fd3d11d3d050f04e2a1851c,
so401 differs from403/42501 and PT409. No default production route changes.

Retire prior owner/epoch first. Near-expiry or explicit forceRefresh invokes one
refresh, requires same owner and a future expiry, persists full session through the
throwing seam and verifies readback before constructing a new owner. Unexpired
snapshot401 retires its candidate/epoch, refreshes once and constructs a wholly new
owner for fresh snapshot admission and empty push consumption. No puts or partial
upload are replayed. A second401 stops, no loop. Permission/generation refusal
never refreshes or signs out. Unauthorized refresh persists nil (verified), signs
out and retains local personal bytes. Stale/cancelled/retired awaited results cannot
persist/build/publish. Original refresh-retirement tests remain, unweakened.

Three new native tests UNRUN: unexpired401 uses two distinct owners and new bearer,
one refresh/two snapshots/no puts;403/42501/PT409/second401 bounded outcomes; throwing
session persistence prevents new owner construction.207 Python PASS.

Keychain concrete checked persistence and final AppStore/host remount hookup are
separate remaining work. Owner+graph factories are still explicit injected seams.
No API compatibility, production activation or native qualification claim.
