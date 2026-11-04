---
name: ate-architecture
description: Use when changing Ate's application architecture, module boundaries, shared services, data ownership, dependency direction, or cross-feature integration.
---

# Ate architecture

## Goal

Preserve a coherent, maintainable architecture across the Ate app and its companion targets.

## Before changing code

1. Read the relevant feature implementation and its callers before proposing a design.
2. Trace the data flow, authoritative state owner, persistence boundary, and side effects.
3. Inspect existing shared abstractions and patterns; prefer extending them over creating parallel infrastructure.
4. Identify affected app, extension, widget, watch, share, and clip targets.
5. State the smallest viable change and its compatibility or migration implications.

## Guardrails

- Keep one authoritative source of truth for each domain concept.
- Respect existing module and target boundaries; avoid introducing dependency cycles.
- Keep domain logic independent of SwiftUI where the current architecture permits.
- Do not move code across layers solely for stylistic consistency.
- Avoid broad refactors bundled with feature work.
- Treat persistence, sync, recovery, and data migration as explicit design concerns.
- Never weaken access control, privacy, or data-integrity guarantees to simplify integration.

## Verification

- Build every affected target where practical.
- Run focused unit and integration tests.
- Check all known consumers of changed interfaces.
- Record what was run, what passed, what was not run, and any remaining risk.

## Delivery

Explain the ownership decision, affected boundaries, alternatives considered, migration needs, and verification evidence. Do not describe a design as implemented until the code and tests demonstrate it.
