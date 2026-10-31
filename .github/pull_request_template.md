## Summary
<!-- What changed, and why? -->

## Type of change
Select at least one. GitHub Actions applies the matching labels automatically.

- [ ] Bug fix — `bug`
- [ ] User-facing feature or improvement — `enhancement`
- [ ] Tests or regression coverage — `testing`
- [ ] CI or build pipeline — `ci`
- [ ] Refactor, dependency, or codebase maintenance — `maintenance`
- [ ] Investigation or technical research — `research`
- [ ] Documentation — `documentation`
- [ ] Release or release-readiness work — `release`

## Stack
Every PR must declare its stack status. Use `None` for standalone PRs.
- **Stack ID:** None
- **Parent PR:** None
- **Position:** None

For a stack root, use a stable ID (e.g. `issue-179`), Parent PR `None`, Position `1/Total`, and target `main`. For a child, use the same ID, the immediate parent PR number (digits only), a position such as `2/3`, and target the parent's head branch. See [stacked PR workflow](../docs/STACKED_PULL_REQUESTS.md).

## Verification
- [ ] Tests added or updated where appropriate
- [ ] Relevant tests run, or the reason they could not be run is stated below
- [ ] CI/build impact reviewed
- [ ] User-facing behavior checked on device/simulator when applicable

**Verification notes**
<!-- Commands, test results, device details, or outstanding limitations. -->

## Risk and rollout
- **Risk:** Low / Medium / High
- **Migration, configuration, or backend changes:** None / Describe
- **Follow-up required:** None / Link issues

## Screenshots / evidence
<!-- Add screenshots or logs where useful. Redact tokens, personal data, and private URLs. -->

## Feature area
Select exactly one.

- [ ] Recipe creation and quality
- [ ] Library and discovery
- [ ] Cooking, timers and widgets
- [ ] Accessibility and navigation
- [ ] Health and journal
- [ ] Shopping List and Settings
- [ ] Sharing, security and reliability
- [ ] Future platform work
- [ ] Product infrastructure and delivery

## Release gate
Select exactly one. This is a delivery commitment, not evidence that acceptance criteria pass.

- [ ] Pilot
- [ ] Public launch
- [ ] No committed release gate

## Priority
Select exactly one, independent of release gate.

- [ ] P0 — Critical / blocks core use or a committed release
- [ ] P1 — High
- [ ] P2 — Normal
- [ ] P3 — Later / low urgency
