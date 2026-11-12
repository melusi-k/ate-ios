# Ate interaction patterns

Status: Draft

Approved direction: text-first pattern records under this directory, [Discussion #487](https://github.com/melusi-k/ate-ios/discussions/487), 12 November 2026. Tracking: [#366](https://github.com/melusi-k/ate-ios/issues/366). Approval of the format does not approve the contents as a canonical pattern library.

| Record | Source coverage | Evidence limit |
| --- | --- | --- |
| [Cook Mode step and finish flow](COOK_MODE.md) | Step navigation, explicit finish, failure and optional reflection handoff | Source audit only; no fresh native/device acceptance |

Each record must state document status, reviewed source SHA/date, entry point, state transitions, side effects/persistence, cancellation/failure/empty paths, accessibility source references and unverified areas. Use [Draft / Current / Archived](../DOCUMENT_STATUS.md) separately from implementation state. Proposed interactions stay visibly separate from observed source.

Follow-up records for sheet-based pickers and per-screen contextual menus remain open; do not infer universal behaviour from one screen. The Figma Patterns & Flows page may link reviewed records later. No Figma content or bindings were edited here, and the broader #366 journey/handoff/ownership criteria remain open.
