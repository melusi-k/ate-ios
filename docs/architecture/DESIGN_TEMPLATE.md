# Design title

Status: Draft

Use Draft / Current / Archived as defined in [document status](../design/DOCUMENT_STATUS.md). Keep review stage and approval evidence separate from status. Promotion requires an owner decision for the exact revision; a template is not approval.
Review stage: Proposed / In review / Approved (record the decision).
Owning issue:
Owner: To confirm.
Source baseline SHA and document revision:
Review budget and selected lenses:

## Problem and evidence

Target user and job, current limitation, evidence versus assumptions. Link the existing lifecycle outcome contract rather than duplicate acceptance inventories.

## Goals and non-goals

State the smallest intended outcome and what will not change.

## Current-state map

For each boundary, cite actual files/symbols and revision: domain owner, public interface, invariants, data scope, side effects, persistence, privacy and evidence status. Distinguish main, unmerged work and verified behavior.

## Critical journeys

Given / When / Then, including unavailable, denied, stale, deleted, corrupt, cancelled and failed states where relevant.

## Architecture and data flow

Describe request, authorization, bounded context, generation if needed, validation, confirmation, domain operation and result. A diagram is optional; every component must be grounded or marked proposed.

## Alternatives and decisions

Option, mechanism, trade-off, failure conditions, decision owner and evidence. Do not present a recommendation as an approved choice.

## Safety and operation

Privacy, data integrity, migration, provenance, cancellation, retry, runtime/OS support, resource bounds, telemetry exclusions, rollback and support implications.

## Detailed implementation plan

Proposed file changes and rationale, interfaces/contracts, dependency order, test fixtures and negative tests, small PR sequence and exact acceptance evidence. No implementation code is required. Mark unknown decisions; an incomplete plan is not implementation-ready.

## Evaluation and release boundaries

Link QA rows and verification records. Separate deterministic CI, eligible real-model inference, physical-device quality and product usefulness. State what has not run. No gate changes implied.

## Review and finding ledger

| ID | Stage/lens | Severity | Scope and evidence | Disposition | Proposed edit | Human decision | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Open questions and approval

Named unresolved decisions, owner, accepted risks, approved exact revision and permitted next step. Leave approval pending until actually given.
