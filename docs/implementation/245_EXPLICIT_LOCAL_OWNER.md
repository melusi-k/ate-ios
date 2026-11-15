# Explicit local owner (#245, follow-on to strict factory)

This dependent slice is still dormant. The next step is enabling and validating
Food Journal, but no production call site switches in this slice.

The owner retains one runtime, the caller's original admitted account writer
lease, actual persisted Journal configuration URL, explicit media/goals and
migration/repair/preservation locations. It uses the existing account-gate then
nested-archive boundary, with no second lock, replacement lease, fallback open,
RPC or disk recovery. A stale/reset-held gate or archive refusal blocks binding
and subsequent effects. Validation alone never advances archive generation.
Binding itself enters one covered boundary and can advance archive control
generation; it is not a non-mutating archive-validation operation.

The strict factory now also requires media location. JournalStore intent media
creation and reflection deletion use that bound location rather than the global
legacy path. Existing constructors retain their legacy path default. The owner
exposes an explicit reset inventory containing exactly its domains, including
personal preservation copies. It does not invoke reset or claim that consumers
have been quiesced. Inventory path validation rejects duplicates and nested
owned directories/store paths; it is not hostile same-UID filesystem race or
symlink protection. Startup recovery must separately validate its actual paths.

Five additive native fixtures cover retained inventory, stale original lease,
archive refusal, wrong store/overlapping locations, and actual bound media
write/delete. They add to the required full-unit union, retaining all prior
entries. Python guards keep both owner and factory without production callers.
Native Swift typechecking and execution remain exact-head CI work.

## Still needed before UI activation

- Complete identity/generation admission and startup recovery, then strict disk
  opening with the original admitted lease.
- Bind real archive capture/import and system-reset participants to this owner.
- Quiesce every legacy consumer and writer, including extensions, widget/watch,
  intents, cover requests, pending cook sessions and startup tasks.
- Switch all canonical UI consumers together. Existing UI/intent readers still
  use global media helpers; this slice does not claim they are switched.
- Verify upgrade/reopen, malformed recovery, stale writer, archive/reset, media,
  ordinary edit/delete and normal-text physical-device journeys.
- Keep #523 workflows and anonymous sign-in OFF. Production Supabase write or
  deploy still needs separate explicit owner approval. Launch is not decided.

No source PR is closed by this slice; branches are kept. Review and exact-head
CI remain required before Reviewer publication/merge.
