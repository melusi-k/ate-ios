# Session refresh race hypothesis and local evidence

Base8516f3b7bc19994712ee23d4cb56893eadd434ff. Native UNRUN.
Owner reports build445 remained installed, so reinstall/re-sign is excluded
from this report. No app-coded24-hour limit found. Live Supabase session/JWT
policy UNKNOWN. Exact phone sign-out cause UNKNOWN. No production calls.

Source permits overlapping syncNow from launch, manual sync, delayed writes,
sign-in and recovery. Cancelling delayed task doesn't join an already-started
network request. Concurrent expired-session requests can use the same refresh
token; original unauthorized catches cleared current session without proving
it was still the request's session. A late rejection can revoke newer sign-in.
This is a possible code path, not measured evidence it caused this incident.

Changes:
- SupabaseAuth owns an actor single-flight per instance. Overlapping refresh
  requests for equal input sessions share a task, including delete-account's
  refresh. Waiting caller cancellation doesn't cancel the shared request.
  Completed flights are removed; no persistent success/failure/token cache.
- Both sync unauthorized catches compare exact captured session AND existing
  writer validator before expireSession. Stale error is ignored. Current
  rejection still clears as before; no waiver of actual authorization failure.
- A late successful refresh cannot overwrite a newer session in dormant graph
  either. Bound graph retains validator. No blanket sync serialization.
- Typed, timestamped local diagnostic events distinguish refresh rejection,
  sync rejection, stale ignored rejection/result, account-switch failure and
  credential read/delete/add/decode failures. Missing item is not read error.
  No tokens, email, IDs, error body, URL, OSStatus payload or user content.
  Existing About diagnostics view/export displays them. All new categories
  are refused by telemetry BEFORE creating network request/payload.
- Keychain delete/add behavior is unchanged except recording failure. Atomic
  update/add with checked result is a SEPARATE follow-up, not claimed fixed.

Limitations: gate covers one SupabaseAuth instance/process, not Watch/other
phones or separate auth clients. It shares only overlapping calls, not stale
requests arriving after the flight completed. Authorization failures still
sign out if current; server rejection mapping401/403 unchanged. Generic failed
account-switch cleanup behavior is unchanged. No claim of exact session epoch
proof beyond existing writer validator plus exact AuthSession comparison.

Native tests added without weakening existing tests: stale refresh and stale
sync rejection in dormant/bound graphs; current rejection still expires;
writer refusal doesn't clear; overlapping held refresh with cancelled waiter;
failed-flight cleanup; differing sessions; typed local category persistence.
Overlap test explicitly requires both callers queued before releasing the
fixture, with bounded yielding and no new sleeps/native allowances/retries.
Swift grammar/Python are not Swift typechecking, actor/macro validation,
Keychain device proof or native qualification. Reviewer must run native.

Original runtime files reconstruct exact base hashes after undoing declared
edits. Older whole-source/folder checks retain original expected hashes after
composing these reversals. New tests preserve original native test bodies.
No timeout/budget/workflow changes, publishing, merges or production writes.
Source PRs close only after Reviewer confirms destination commit; branches kept.
