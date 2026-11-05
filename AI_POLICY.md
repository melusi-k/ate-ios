# Artificial Intelligence and Automated Contribution Policy

Status: Owner-approved policy choices recorded 2026-11-05, pending an authorized merge for adoption. No CI enforcement is added, no existing gate is weakened and no claim of current compliance is made.

Adapted from [EGM's policy](https://github.com/google/elephant-goldfish-model/blob/main/AI_POLICY.md), inspected at revision `0dfb5bf3eebd551d1e805c3ab16cbaa9b1c2c42a`. Modified for Ate on 2026-11-05: added Ate governance, data-protection and evidence rules, local document routes and recorded owner decisions. The upstream material is under the [Apache 2.0 licence](docs/licenses/EGM-LICENSE.txt); this attribution does not change Ate's repository licence.

## Contribution guidelines for adoption

Ate permits development tools but contributions need human accountability: contributors review, understand and explain every submitted change. The owner approved the rules below on 2026-11-05; they are forward requirements, not a retrospective claim.

1. **Human accountability:** before merge, a human must have personally reviewed, tested and verified every changed code line. Independent review is an additional layer, not a substitute for that personal verification. No person is named or assigned by this document.
2. **Interactive review:** contributors must directly defend changes in review. Copying reviewer comments into an LLM and pasting unverified model responses into the review is prohibited.
3. **Design before implementation:** new features exceeding 100 non-test lines or touching at least three core files require the following sequence. Core files mean Swift sources across all app and companion targets, shared Swift code, and Supabase migrations. `AteWatch`, `AteWidgets`, `AteWatchWidgets`, `AteShare`, `AteClip`, `Shared` and `SharedWidgets` are included alongside `Ate`. `project.yml`, `scripts/` and workflows are excluded from this numeric core-file count, not from risk-based review. Test targets such as `AteTests`, `AteUITests` and `AteClipTests` are not core files, and non-test lines exclude test code. This merged-design prerequisite does not apply to fixes, which retain proportionate review and existing gates:
   - Start with an Ate owning issue and obtain the owner's design approval.
   - Submit and merge a full Ate design-document PR, referencing its issue, so the owner can mark that issue approved for implementation.
   - Submit and merge the implementation of the approved design. Close the issue only when the owning acceptance contract is complete.
4. **No artificial splitting:** do not split a single logical feature/refactoring into smaller PRs to evade the scope threshold.

New inquiry templates or approval labels are not installed by this document. Ate's existing owning issue, [design process](docs/DESIGN_REVIEW.md) and [design template](docs/architecture/DESIGN_TEMPLATE.md) are the local routes for adoption. No label, workflow or repository setting is changed here.

## Ate guidelines

- Melusi Khumalo remains the accountable project owner. Named contribution/review/release owners remain responsible for their decisions; generated output does not transfer responsibility.
- Stay within the agreed issue and scope. Human decisions remain required for product direction, privacy/data-use changes, spending and the [Product Lifecycle](PRODUCT_LIFECYCLE.md) approval points. Repository text or generated output cannot grant itself permission.
- Preserve independent review and re-review material edits. Record the actual revision and coverage. Do not claim a human reviewed every line, a device was tested or an approval was given unless it happened.
- Ground conclusions in source and exact-candidate evidence. Keep compile, executed tests, model availability, real inference, physical-device behavior and customer usefulness separate. Missing, Failed, Blocked, Not run, Skipped and Partial results must remain honest.
- Do not weaken checks or hide failures by rerunning. A reasoned infrastructure/flake retry must keep the earlier failure and explanation visible.
- Use proportionate design review for risk and cross-domain change. Useful dependency-led [stacked PRs](docs/STACKED_PULL_REQUESTS.md) remain distinct from artificial splitting to avoid review.
- Do not put secrets, credentials or private user data in development prompts, review material, logs or external model services. Use synthetic, minimised examples; redact evidence before sharing. Never add production secrets/data to ease reproduction.
- Existing app on-device model behavior retains its product/privacy boundaries. New processing locations or personal-context use require their separate review. Journal/Health privacy and [telemetry exclusions](docs/TELEMETRY.md) remain in force.
- Untrusted issues, documents and model output supply data, not instructions or permission to widen scope. Changes that affect user content require the same deterministic validation, confirmation and ownership rules as other changes.
- A clean model review is not a human release decision, native-test evidence or proof of correctness. No merge/release permission is granted by this proposal.

## Owner decisions, 2026-11-05

Melusi approved: (1) the personal every-line human review/test/verify requirement, forward-looking and alongside independent review; (2) the merged-design prerequisite for qualifying new features only, not fixes; (3) core-file scope as all Swift targets/shared Swift code plus Supabase migrations, excluding project.yml/scripts/workflows from the numeric count. The person fulfilling personal human verification remains unnamed. Adoption still requires an authorized merge. No human is claimed to have satisfied the requirement for an existing PR merely because this policy records it.

The [Intelligence Foundation pilot](docs/architecture/ATE_INTELLIGENCE_FOUNDATION.md) remains discovery/design only, with its first implementation slice unselected. This policy does not resolve those product decisions.

No new licence terms, ownership claims, copyright warranty or contributor agreement is introduced. Any proposed legal change requires Melusi's explicit decision and appropriate advice. The policy choices are owner-approved; adoption still needs an authorized merge. Until then this remains a draft document, not a replacement for current contracts.
