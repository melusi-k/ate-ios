# Starting work on Ate

This is a short route through existing repository contracts, not a second build or QA policy. It applies to the native SwiftUI app and its Supabase backend.

## Find the owner and scope first

Read the owning issue and [Product Lifecycle](../PRODUCT_LIFECYCLE.md), then inspect the current source and relevant open PRs. Record what is on main, what is unmerged and what has been verified. Reuse the [acceptance inventory](MVP_CHECKLIST.md) and [QA matrix](QA_MATRIX.md). Do not open a competing persistence or feature implementation when a canonical owner already exists.

For a substantial boundary change, use [design review](DESIGN_REVIEW.md) and [the design template](architecture/DESIGN_TEMPLATE.md). The [contribution policy](../AI_POLICY.md) records owner-approved choices pending merge/adoption, with core-source boundaries defined and the personal human reviewer left unnamed. Do not present an unmerged policy as an active replacement for existing contracts.

## Understand the repository

- `Ate/`: app code; models, logic, stores, services, views and intents.
- `AteTests/`, `AteUITests/`, `AteClipTests/`: automated tests.
- Companion targets: `AteWatch/`, `AteWidgets/`, `AteWatchWidgets/`, `AteShare/`, `AteClip/`; shared code in `Shared/` and `SharedWidgets/`.
- `supabase/`: backend functions and migrations; preserve ownership/RLS and never embed secret keys in the app.
- `project.yml`: XcodeGen project definition. `scripts/`: build/validation helpers.

## Prepare a local candidate

Follow the repository [local build instructions](../README.md) and [guidelines](../AGENTS.md). On a suitable Mac, `bash scripts/prepare-local-build.sh` generates the Xcode project with local version/Git metadata. Do not commit generated local version churn. Inspect the script and required tooling before running it; this guide does not install tools or change credentials.

Use the exact simulator/device policy in [CI.md](CI.md) for comparable qualification. Older examples in repository guidance are not permission for silent CI device fallback. Record the actual local Xcode, device/runtime and SHA; a local build on a different environment is not an exact CI substitute.

## Make a bounded change

Use the surrounding code style, focused tests and a small reviewable diff. If acceptance IDs change, use the existing checklist generation/validation route; do not hand-edit generated source. Preserve typed data, account ownership, recovery, privacy, unsupported-device behavior and rollback paths relevant to the change.

Run applicable script/unit/UI tests only in an authorized environment. Backend E2E can contact a real backend; inspect its scope and authorization before running, rather than treating it as a harmless local checklist. Model mocks, real inference and physical-device quality are distinct evidence lanes.

## Hand off truthfully

Complete the PR template and [stack metadata](STACKED_PULL_REQUESTS.md). Link the issue, exact candidate SHA, meaningful design decisions, tests actually run and artifacts, independent review, limitations and follow-up. For native/UI changes, inspect the result and include useful screenshots or logs as the PR template requests. Failed, skipped, blocked and not-run work must remain visible. Existing merge/release policy and human decisions still govern; this guide grants no new permission.
