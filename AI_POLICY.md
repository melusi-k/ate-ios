# Artificial Intelligence and Automated Contribution Policy

Status: Proposed, pending human policy decisions below. No existing gate is weakened and no claim of current compliance is made.

Adapted from [EGM's policy](https://github.com/google/elephant-goldfish-model/blob/main/AI_POLICY.md), inspected at revision `0dfb5bf3eebd551d1e805c3ab16cbaa9b1c2c42a`. Modified for Ate on 2026-11-05: added Ate governance, data-protection and evidence rules, local document routes and explicit unresolved differences. The upstream material is under the [Apache 2.0 licence](docs/licenses/EGM-LICENSE.txt); this attribution does not change Ate's repository licence.

## Contribution guidelines proposed for Ate

Ate permits development tools but contributions need human accountability: contributors review, understand and explain every submitted change. The following rules are proposed, with the decisions below still open.

1. **Human accountability:** every PR must have a human author who has personally reviewed, tested and verified every line of changed code.
2. **Interactive review:** contributors must directly defend changes in review. Copying maintainer review comments into an LLM and pasting unverified model responses into the review is prohibited.
3. **Design before implementation:** features or large changes (`> 100` non-test lines; the proposed three-core-file mapping is still awaiting approval) should follow this sequence:
   - Start with an Ate owning issue and obtain the owner's design approval.
   - Submit and merge a full Ate design-document PR, referencing its issue, so the owner can mark that issue approved for implementation.
   - Submit and merge the implementation of the approved design. Close the issue only when the owning acceptance contract is complete.
4. **No artificial splitting:** do not split a single logical feature/refactoring into smaller PRs to evade the scope threshold.

New inquiry templates or approval labels are not installed by this document. Ate's existing owning issue, [design process](docs/DESIGN_REVIEW.md) and [design template](docs/architecture/DESIGN_TEMPLATE.md) are the proposed local routes, subject to the decisions below. No label, workflow or repository setting is changed here.

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

## Human decisions required before adoption

These differences are visible rather than silently resolved:

1. The proposed every-line rule requires a human author to personally review/test/verify every changed code line. Ate's existing process records independent review plus exact-candidate tests and human lifecycle decisions. Confirm whether the stricter personal every-line requirement is to become an additional rule, and who fulfills it. Do not claim it is already satisfied.
2. The proposed size rule uses `> 100` non-test lines or a three-core-file threshold. Confirm whether core files should mean Ate app target sources plus Supabase migrations. This mapping is not yet approved.
3. The proposed design gate requires a merged design PR and design/implementation approval-label sequence. Ate currently uses risk-proportionate design and lifecycle approvals. Confirm whether to add the strict merge/label prerequisite or retain the existing human-approved design path. No merge of a design is authorized to satisfy this sequence while the draft hold applies.

Proposed options for the owner, not selected: make the every-line personal requirement a forward requirement fulfilled by Melusi alongside independent review; apply the merged-design gate to new features only; map core files to app target sources and Supabase migrations. These options need his answer and are not current rules.

The [Intelligence Foundation pilot](docs/architecture/ATE_INTELLIGENCE_FOUNDATION.md) remains discovery/design only, with its first implementation slice unselected. This policy does not resolve those product decisions.

No new licence terms, ownership claims, copyright warranty or contributor agreement is introduced. Any proposed legal change requires Melusi's explicit decision and appropriate advice. Adoption needs human approval of these policy choices and an authorized merge. Until then this is a draft proposal, not a replacement for current contracts.
