# Complete sync fixture model qualification

Base d21fd1cf5022a953b3ec8582b4ebd16892b504cd. Hypothesis, native UNRUN.

Current Nutrition unit log: interruption matrix opens a JournalEntry schema
without dayKey/kindRaw/recipeSnapshotsRaw, seeds, enters commit1 at
beforeIntentWrite and traps Optional<Any> to String. Both edit tests use a
current-schema container, then legacy-typed fetch/edit and fail save with
required kindRaw=null (NSCocoa1570). Older5390743 also fails all three
named tests. These are real errors, not idle/stall diagnoses.

Test-target LegacyJournalStoreUpgradeTests intentionally declares a legacy
JournalEntry class with precisely those missing fields. A prior patch fixed
seedJournal's constructor only. Five references remained unqualified:
three FetchDescriptor generics and both disk matrix ModelContainer calls.
This packet qualifies exactly those five references as Ate.JournalEntry.
The third fetch is the sibling delete-during-upload case and must use the
same production model. No new defaults or values mask a bad production row.
Legacy upgrade fixture stays byte-identical. No production changes,
migrations, assertion changes, catches, retries, time or budget changes.

Whole original UserDataSyncTests reconstructs to exact base SHA256 after
reversing these substitutions, preserving every action, assertion and
checkpoint. Older whole-file/folder contracts compose that reversal with
unchanged expected hashes. No historical Git objects needed by new checks.

Native must prove current schema in BOTH matrix opens, full interruption
matrix convergence, edits preserved, stale commits refused, pending intents
preserved, delete sibling passes and legacy upgrade still passes. Static
checks are not Swift typechecking, macro expansion or native qualification.
Nutrition UI keyboard/Settings geometry timeout remains separate and open.

Source PRs close only after Reviewer confirms destination commit; branches kept.
