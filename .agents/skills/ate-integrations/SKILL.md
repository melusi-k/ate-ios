---
name: ate-integrations
description: Use when connecting Ate to Apple platform capabilities, App Intents, Shortcuts, Siri, Spotlight, widgets, Foundation Models, Apple Intelligence, or external services.
---

# Ate platform integrations

## Establish the contract first

- Identify the user capability being exposed and the system surface that invokes it.
- Inspect existing domain services and reuse their validated operations; do not reimplement business rules in an intent or extension.
- Define inputs, outputs, authentication requirements, permissions, privacy boundaries, and failure behavior.
- Determine availability and behavior across supported OS versions and app/extension targets.
- Keep the app functional when the system capability is unavailable or the user has not granted permission.

## App Intents and system actions

- Model actions around clear user intent and predictable outcomes.
- Use typed parameters and useful, localized display representations.
- Request confirmation for destructive, externally visible, or consequential actions.
- Do not expose private user content through overly broad entity queries or logging.
- Ensure intent execution is safe when invoked outside the foreground app and handles stale or missing state.

## AI and contextual features

- Treat model output as untrusted input; validate it before applying changes.
- Keep user approval in control of writes, sharing, deletion, and other consequential actions.
- Minimize the context sent to models and avoid exposing secrets or unrelated personal data.
- Provide graceful fallback and transparent error states when models, network access, or platform APIs are unavailable.
- Separate capability exposure from autonomous behavior; do not imply an action occurred until its result is confirmed.

## Verification

Test supported OS availability, permission-denied behavior, missing data, malformed parameters, cancellation, failure, and successful execution. Document platform prerequisites and any behavior that requires a physical device.
