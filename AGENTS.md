# Repository Guidelines

## Project Structure & Module Organization

This is a native SwiftUI app generated from `project.yml` with XcodeGen. `Ate/` contains the iOS app, organized by feature and supporting layer. Companion targets live in `AteWatch/`, `AteWidgets/`, `AteWatchWidgets/`, `AteShare/`, and `AteClip/`; shared extension code is in `Shared/` and `SharedWidgets/`. Unit tests are in `AteTests/` and `AteClipTests/`; UI tests are in `AteUITests/`. Documentation is in `docs/`; Supabase functions and migrations are in `supabase/`; build and validation helpers are in `scripts/`.

## Build, Test, and Development Commands

- `brew install xcodegen` installs XcodeGen.
- `bash scripts/prepare-local-build.sh` generates `Ate.xcodeproj` with local version and Git metadata. Run after checkout or branch changes; do not commit local generated version changes.
- `open Ate.xcodeproj` opens the project in Xcode 26 (iOS 26 SDK required for Foundation Models).
- `xcodebuild -project Ate.xcodeproj -scheme Ate -destination 'platform=iOS Simulator,name=iPhone 17' build` builds for the simulator; adjust the simulator name as needed.
- `xcodebuild -project Ate.xcodeproj -scheme Ate -destination 'platform=iOS Simulator,name=iPhone 17' test` runs the scheme's tests. CI checks are in `.github/workflows/compile-check.yml`; broader QA guidance is in `docs/QA.md`.

## Coding Style & Naming Conventions

Follow the surrounding Swift style: four-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for properties, functions, and enum cases. Use descriptive filenames matching the primary type (for example, `RecipeMatcher.swift`). Python scripts use kebab-case filenames. Localization lives in `Ate/Resources/Localizable.xcstrings`; update generated checklists through scripts.

## Testing Guidelines

Add or update focused XCTest coverage in `AteTests/` for logic and service behavior, and `AteUITests/` for user flows. Name test files after the feature or behavior and test methods descriptively, such as `testRecipe...`. Run relevant tests before submitting. Checklist IDs and QA artifacts are source-controlled contracts: use `scripts/check-ids.py` and the checklist generation scripts when changing them, and confirm generated files remain in sync.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, usually with prefixes such as `feat:`, `fix:`, `build:`, `ci:`, or `docs:`; keep the subject focused. Complete `.github/pull_request_template.md`, explain changes, link issues, and include test evidence. Add screenshots for UI changes; update docs or QA checklists when acceptance criteria change.

## Security & Configuration

Never commit credentials, signing material, or Supabase secret keys. App configuration belongs in `project.yml` build settings and secrets belong in GitHub Actions secrets. Keep database access protected by the existing Supabase policies and migrations; include security implications when modifying auth, sharing, or stored user data.
