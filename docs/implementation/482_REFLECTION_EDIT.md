# Reflection edit failure safety (#482)

Base main e6bcae0ef9ca1e156bd06ab6440609dfd921e379. Enabled legacy reflections,
not unified Food Journal activation. JournalStore.update now returns true only
when its isolated context saved; empty/unavailable/missing/non-reflection and
write-boundary/save errors return false. Failed context rolls back, retained
reader is updated only after success, unrelated pending main-context work is not
committed or discarded. Save uncertainty is not claimed as success.

Detail editor keeps exact draft, stays open and shows an inline retry message
on false; no parent revision, reload, QA success or dismissal. On true only,
increment parent journalRevision, dismiss, reload committed entry and record QA.
A UITesting-only one-shot edit failure allows a real UI retry in the same sheet.
It does not affect creating entries or production saves.

Two native unit methods cover injected failure/retry, unchanged reader/date,
unrelated pending work and refusal states. One native UI method captures failed
retained draft then successful retry and refreshed history. Existing normal-size
Journal worker includes them, requires all three exact names, retains existing
selectors/timeouts/jobs and attachment export. Original CRUD journey unchanged.

Python/source checks are not native or visual acceptance. Swift/native/device/
new pixels NOT RUN; inspect actual error/readability/draft/history screenshots
before UI acceptance. No issue closure or activation. Build-focus is separately
re-anchored to the exact runtime commit and includes current service evidence,
without changing strict ancestry/blob validation.
