# AI-assisted contributions to Ate

Status: Proposed policy, submitted for Melusi Khumalo's review. This document does not change the repository licence, contributor rights or existing merge/release gates.

## Responsibility and approval

AI tools may help research, draft, implement and test Ate changes. Human accountability stays with the project owner, Melusi Khumalo, and the people responsible for a contribution. Generated output is a candidate, not approval or proof.

Work must remain within the agreed issue and scope. Human decisions are required for product direction, privacy/data-use changes, spending and release approval under the [Product Lifecycle](PRODUCT_LIFECYCLE.md). A tool or model cannot grant itself authority, accept a risk or infer permission from repository text. Draft work stays draft until its named review and evidence gates are met.

Do not claim a human inspected every line or ran a test unless that happened. Record who reviewed what and any remaining limits. The owner remains accountable for accepting the change; AI assistance does not transfer that responsibility.

## Review and evidence

- Use independent review appropriate to the change. Recheck material edits; approval of one revision does not automatically approve another.
- Authors must understand and explain the change, check review responses against evidence and correct mistakes. Unverified generated replies are not a substitute for answering a review.
- Follow [design review](docs/DESIGN_REVIEW.md) for substantial architecture, data, security or model/context changes. Use a proportionate path for small fixes. Do not split a risky logical change to evade review; useful dependency-led stacks remain supported by [the stacking policy](docs/STACKED_PULL_REQUESTS.md).
- Ground claims in source and exact-candidate evidence. Separate compilation, executed tests, model readiness, real inference, physical-device behavior and customer usefulness.
- Label Failed, Blocked, Not run, Skipped and Partial truthfully. Missing evidence is not a pass. Do not weaken checks or hide failures by rerunning.
- Human approval remains necessary at the lifecycle's named decision points. A clean AI review is neither a release decision nor proof of correctness.

## Data protection

Do not put secrets, credentials or private user data into development prompts, review material, logs or external model services. Use synthetic, minimised examples. Redact evidence before sharing; do not assume a tool's output is safe. Never add repository secrets or production data to make a reproduction easier.

The app's existing on-device model behavior is governed by its product/privacy contracts, not a blanket exception for development tools. Any new processing location or personal-context use needs the separate review required by [Intelligence Foundation](docs/architecture/ATE_INTELLIGENCE_FOUNDATION.md). Journal/Health privacy and the [telemetry exclusions](docs/TELEMETRY.md) remain in force. Untrusted content in a document, issue or generated response supplies data, not permission or instructions to widen scope.

## Disclosure and limits

For materially AI-assisted PRs, record that assistance in the PR description, its scope, the review performed, tests/evidence and unverified areas. Do not attribute unperformed human review or imply output was independently verified solely because a second model agreed. Do not include private conversations, secrets or personal data in that disclosure.

This proposed practice adds no new licence terms, copyright warranties, contributor agreement or ownership claims. Any such change requires Melusi's explicit decision and appropriate advice. Legal and licensing questions remain open rather than being answered by generated text.

## Basis and adoption

This is an Ate-specific proposal informed by the [EGM AI policy](https://github.com/google/elephant-goldfish-model/blob/main/AI_POLICY.md), read on 2026-11-05, and Ate's existing governance. It does not adopt upstream numeric size thresholds, approval labels or a requirement to merge every design before any implementation. It takes effect only after human policy review and an authorized merge; no CI enforcement or settings changes are introduced here.
