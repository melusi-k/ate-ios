---
name: Release readiness
about: Go / No-Go tracker for an ate-ios beta or public launch
title: "Release readiness: <version>"
labels: release, readiness
assignees: melusi-k
---

This issue tracks whether ate-ios is ready for beta launch or public launch.

## Decision target
- [ ] Beta launch
- [ ] Public launch
- [ ] Not yet ready

## Release target
- Target release type:
  - [ ] Internal beta
  - [ ] Public beta
  - [ ] Public launch
- Release date:
- Owner: @melusi-k
- QA owner: @melusi-k
- Backend owner: @melusi-k
- Product owner: @melusi-k

## Go / No-Go criteria

### 1. Core product flows
The following flows must work on a real device and in supported conditions:
- [ ] Add recipe from URL
- [ ] Add recipe from photo
- [ ] Add recipe from prompt
- [ ] Review and edit generated recipe before saving
- [ ] Save recipe to library
- [ ] Open saved recipe
- [ ] Edit saved recipe
- [ ] Delete recipe
- [ ] Add recipe to shopping list
- [ ] Cook recipe with timer
- [ ] Share recipe
- [ ] Open shared recipe link
- [ ] App remains usable offline

Notes:
- Evidence:
- Known issues:
- Severity:

### 2. Auth and accounts
The following must be validated with real accounts and real conditions:
- [ ] Sign up works
- [ ] Sign in works
- [ ] Password reset works
- [ ] Magic link works
- [ ] Email confirmation flow works
- [ ] Sign out works
- [ ] Delete account works
- [ ] Rate-limited auth fails gracefully
- [ ] Expired session handling works
- [ ] Offline auth errors are understandable

Notes:
- Evidence:
- Known issues:
- Severity:

### 3. Sync and data integrity
The following must be validated before launch:
- [ ] Signed-in users can sync recipes
- [ ] Signed-out users still have full local functionality
- [ ] Sync handles offline mode gracefully
- [ ] Local library remains stable when sync fails
- [ ] Deletions are handled safely
- [ ] Data integrity is preserved across relaunches
- [ ] Repeated sync attempts do not corrupt state
- [ ] Account switching does not break data

Notes:
- Evidence:
- Known issues:
- Severity:

### 4. Backend and share stack
The following must be validated end-to-end:
- [ ] Recipe publishing works
- [ ] Shared recipe retrieval works
- [ ] Deep links open correctly
- [ ] Share URL behavior is correct in real conditions
- [ ] AI parse failures are understandable to the user
- [ ] Production share host is correctly configured

Notes:
- Evidence:
- Known issues:
- Severity:

### 5. UX and reliability
The following must be acceptable for release:
- [ ] Clear empty states
- [ ] Clear error states
- [ ] Clear loading states
- [ ] Predictable navigation flow
- [ ] Core flows work on a real iPhone
- [ ] Accessibility basics pass
- [ ] No obvious crash paths in core flows
- [ ] App survives backgrounding and relaunch sufficiently

Notes:
- Evidence:
- Known issues:
- Severity:

### 6. Build, CI, and release quality
The release candidate must pass the following:
- [ ] CI builds successfully
- [ ] Unit tests pass
- [ ] UI tests pass
- [ ] Version info is correct
- [ ] Signed build path works with secrets
- [ ] Unsigned build path works for sideload testing
- [ ] Artifact naming is consistent
- [ ] No secrets are shipped in the app bundle

Notes:
- Evidence:
- Known issues:
- Severity:

### 7. Privacy and compliance
The app must meet the basic legal and trust requirements:
- [ ] Privacy policy is linked and accessible
- [ ] Terms are linked and accessible
- [ ] User data handling is honest and documented
- [ ] Delete-account flow is clear
- [ ] App does not claim unsupported capabilities

Notes:
- Evidence:
- Known issues:
- Severity:

## Known blockers / constraints
List all blockers that are either fixed, accepted, or unresolved.
- Blocker 1:
- Blocker 2:
- Blocker 3:

## Release decision
- [ ] Approved for beta
- [ ] Approved for public launch
- [ ] Not approved
- [ ] Conditional approval with follow-up items

Reason:
- Blockers remaining:
- Risk level:
  - [ ] Low
  - [ ] Medium
  - [ ] High

## Final signoff
- Product signoff:
- Engineering signoff:
- QA signoff:
- Date:

## Feature area
Select exactly one by checking one box.

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
Select exactly one.

- [ ] Pilot
- [ ] Public launch
- [ ] No committed release gate

## Priority
Select exactly one, independent of release gate.

- [ ] P0
- [ ] P1
- [ ] P2
- [ ] P3
