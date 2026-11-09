---
name: ate-journal
description: Use when changing Ate Journal entries, editing and archive flows, persistence, recovery, sync, navigation, or consumers of Journal data.
---

# Ate Journal

## Safety and ownership

Journal data is user-authored and must be treated as high-integrity personal content. Before changing it, locate the authoritative model/store and trace every reader and writer. Do not create a second Journal source of truth.

## Change workflow

1. Map the entry lifecycle: create, read, edit, delete/archive, restore, and any export or sync paths affected by the change.
2. Identify persistence transactions, identifiers, ordering, timestamps, and migration behavior.
3. Check how screens, widgets, search, summaries, and other consumers obtain Journal state.
4. Preserve existing recovery and archive semantics; make destructive operations explicit and recoverable where the product contract requires it.
5. Add focused tests for state transitions and failure/recovery cases.

## Guardrails

- Never silently discard, overwrite, or reinterpret user-authored content.
- Avoid lossy transformations and implicit destructive migrations.
- Keep archive and active-entry semantics consistent across all consumers.
- Handle partial failures without presenting unsaved changes as persisted.
- Protect Journal content in logs, diagnostics, and analytics.

## Acceptance evidence

Verify the changed state journeys and affected consumers. Distinguish individual journey passes from complete Journal feature acceptance. Document any untested recovery, sync, migration, or device behavior.
