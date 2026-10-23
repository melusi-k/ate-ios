# Ate telemetry contract

## Current phase

Ate's existing `DiagnosticHistory` remains the source of local diagnostics. Typed product/reliability categories are recorded locally only. The current privacy promise remains unchanged: no diagnostic event is sent to an external provider.

## Event rules

- Event names are a closed Swift enum; callers cannot attach arbitrary fields or user-provided strings.
- Planned product event categories include recipe import outcome, recipe save, cooking completion, insight interaction, and sync outcome. In this initial slice, only recipe-save handoff and explicit cooking completion are emitted; import, insight, and sync categories are reserved for follow-up wiring at confirmed outcome boundaries.
- Recipe-save telemetry is recorded only after the normalized card is handed to the owning save callback. The callback should remain the single success boundary; do not add a success event before the save action.
- Never include recipe titles or ingredients, prompts, screenshots, URLs, raw error messages, account/user/device identifiers, Health data, or precise location.
- Local diagnostic history remains bounded, exportable and clearable using the existing Settings screen.
- Product event recording must not affect feature success/failure, block UI work, or make release gates less strict.

## Remote debug streaming: separate gated phase

Remote streaming is not enabled by this change. Before it is implemented, the team must approve a receiver and retention/deletion policy, apply server-side access controls and rate limits, and update the privacy policy, subprocessors/data map, policy history, and beta tester disclosures together. It must be disabled by default, require explicit revocable opt-in in beta builds, use only an allowlisted schema, and never ship a Supabase service-role secret in the app. Opt-out must stop future uploads; queued events must be bounded and clearable. A remote upload must never be required for app operation.

## CI telemetry

CI emits a JSON artifact derived from GitHub Actions run/job/step metadata. It includes the commit SHA, workflow/run identifiers, runner metadata, outcomes and available timing values. Creation-to-start durations are explicitly named as such; they are not described as queue time because run creation is not a queue timestamp. Missing timings stay null. The collection is best-effort and non-blocking; it must not change build/test outcomes. No source files, logs, secrets, app data, or tester data are collected by this artifact.
