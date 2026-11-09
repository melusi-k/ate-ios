---
name: ate-swiftui
description: Use when implementing or reviewing Ate SwiftUI screens, navigation, reusable components, interaction states, accessibility, or design-system behavior.
---

# Ate SwiftUI

## Before implementation

- Inspect nearby screens and shared components for established visual and interaction patterns.
- Trace navigation ownership and presentation state before changing routes, sheets, menus, or tabs.
- Check loading, empty, error, disabled, and success states—not only the happy path.
- Identify whether the view is used by iPhone, iPad, widgets, or another target.

## Implementation rules

- Prefer existing design-system components, tokens, and modifiers over one-off styling.
- Keep view responsibilities focused; move non-view business logic into the established domain/service layer.
- Preserve state ownership and data flow. Avoid duplicating persisted or shared state inside views.
- Keep navigation changes scoped and preserve deep-link and restoration behavior where applicable.
- Support Dynamic Type, VoiceOver, adequate hit targets, and readable contrast.
- Use meaningful accessibility labels, values, and identifiers; do not rely on visual text alone for UI automation.
- Avoid adding animation where it impairs responsiveness or creates unreliable UI-test synchronization.

## Verification

- Build the affected scheme/target.
- Run relevant UI and unit tests.
- Inspect the affected flow on a simulator at relevant text sizes and appearance settings when possible.
- Report simulator/device verification separately; a successful build is not UI acceptance.
