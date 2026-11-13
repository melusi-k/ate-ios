# Slice 12: standalone shared writer readiness and redo refusal

Dormant explicit route, not installed into app or extensions. Legacy defaults and
Food Journal/archive activation remain unchanged.

A minimal nonpersonal readiness marker contains only the original common writer
UUID epoch. The app owner publishes it under its retained real gate/lease AFTER
admission, strict resources replay, matching bound session/owner/journal directory
and another strict raw inventory check. Marker uses exclusive temp, complete write,
fsync/fullfsync, rename, parent sync and readback. Corrupt or partial ready evidence
is retained and blocks. A valid prior epoch may only be replaced by the newly
admitted app owner, not an extension.

makeSharedWriterBoundary returns a synchronous app adapter that requires MainActor
(main-thread guard refuses background misuse), actual owner admission and marker
plus redo check on EVERY effect under the same account gate. It does not install or
replace any global boundary. Final remount must use explicit retired-old replacement.

Shared RecipeShoppingSharedWriterControl.makeExtensionBoundary uses the SAME
control-directory reset reader, flock, original captured epoch and an each-effect
ready check. No fallback or marker creation. A newly launched extension after epoch
rotation cannot write using the prior ready marker before re-admission/replay. An
old captured boundary never refreshes its lease and remains stale after rotation.

Both paths refuse while pending-v1.json, its .tmp, or metadata-v1.json.tmp exists
(including symlink/corrupt evidence). Missing/unsafe commit directory refuses.
Ready checks run inside the effect gate, not just at creation. No Food Journal
archive generation is advanced in this standalone route.

Four native tests UNRUN: no writes/marker before readiness; old and freshly captured
extension leases across epoch transition; all retained redo/temp evidence refused
without deletion; corrupt/temp marker refusal and reset invalidation.207 Python PASS.

Open: actual app/extension startup wiring and reset inventory must choose this
route together, not only the app factory. Current production defaults still legacy.
The epoch-only readiness marker can remain as minimal nonpersonal control after
Clear all, since reset epoch rotation invalidates it. Personal redo/authority files
are independently erased via the exact journal reset component.
