# Checked Keychain session persistence, separate hypothesis

Incremental base4ec571572dd448c106d4e232e00b1701f3e67b20 (auth packet1).
Original hosted source8516f3b7bc19994712ee23d4cb56893eadd434ff.
Native UNRUN. This packet is NOT independent of packet1.

Old save deleted an existing credential before adding replacement, ignored
OSStatus, then published new in-memory session/watch state regardless. A
failed add could leave the next launch with no saved sign-in. No evidence
proves that happened to the owner's build445. Supabase session policy UNKNOWN.

Replacement save uses SecItemUpdate; only errSecItemNotFound permits Add.
Other failures return false without deleting previous bytes. Add failure or
concurrent duplicate returns false honestly, without delete or retry. Explicit
nil removes credential, treating success/missing as removed and all other
statuses as failure. Keychain scope, service/account, accessibility unchanged.
This applies to existing session and PKCE callers; existing non-session
callers may discard Bool (not claimed fully checked). New diagnostic categories
remain local-only under packet1. No raw error/status or secrets persisted.

AppStore.setSession encodes without collapsing an encoding failure into nil,
checks save/delete success BEFORE changing in-memory session or publishing to
Watch. Failure flows through existing sign-in/session-write failure handling.
This is not a multi-resource transaction: a writer effect can still fail after
successful keychain/session/watch publication. Existing partial-failure copy
and tests remain. OS success is not hardware-durability proof or refresh-token
rollback: the server may already have rotated a token before local save fails.
A stale old token can remain if the OS refuses update. No retry/waiver added.

Operations are synchronous injectable closures for native tests without
writing device credentials. Tests cover update success/no delete; missing->add;
auth/locked denial no add/delete; duplicate-add failure no retry; explicit
removal failure; failed sign-in save keeps old in-memory session; failed
credential removal doesn't falsely claim expired/sign-out. A store-local save
closure defaults to live checked save, allowing deterministic failure tests.
Original native test bodies preserved, older guards compose exact reversals.
No production traffic/migrations, publishing or merges. No UI/native pixels
claimed; native Security API behavior and real relaunch persistence UNRUN.

Source PRs close only after Reviewer confirms destination commit; branches kept.
