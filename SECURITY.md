# Security policy

## Supported versions

Security fixes target the latest TestFlight build and current main branch. Older builds are not supported. Use the latest available build when checking an issue, and include the exact version, build number and source commit when known. This support policy is not a claim that a build has passed every security or acceptance check.

## Scope

This policy covers Ate's iOS and iPad app, watchOS app, future macOS, tvOS and CarPlay work, Supabase backend rules and access controls, and repository CI/workflows. Listing a platform does not mean an app for it is currently released or supported in production.

## Report a vulnerability privately

Use this repository's **Security > Advisories > Report a vulnerability** form:

https://github.com/melusi-k/ate-ios/security/advisories/new

Do not report vulnerability details in a public issue, Discussion, pull request or commit. Private vulnerability reporting is a repository setting, separate from this file. If the private reporting form is unavailable, do not post details publicly. Ask a repository maintainer to enable private reporting or provide a private route, without including the vulnerability details in that request.

Include the affected version/build or commit, affected platform, expected and actual behavior, the security impact, and the smallest safe reproduction using synthetic data. Provide only the detail needed to investigate. Do not include passwords, API keys, access or refresh tokens, signing credentials, private keys, authentication cookies, personal data, user content or production database exports, even in a private report. Redact logs and screenshots before sharing them.

## Safe handling

Test only with accounts and systems you own or have explicit permission to test. Do not access another person's data, disrupt service, or use a real user's records to demonstrate a problem. Stop if a test exposes private data; describe the type of exposure without copying the data into the report.

Secrets belong in approved secret storage, not source files, test fixtures, screenshots, logs or release notes. Use least-privilege tokens for CI and backend access. Public client configuration is not authority to expose privileged Supabase credentials or Sentry authentication tokens. If a credential may have been exposed, revoke or rotate it through its provider and report the affected credential type and location, not the secret itself. Removing a string from the latest commit alone does not invalidate it or remove it from history.

Maintainers will assess reports privately and coordinate any fix and disclosure. This policy makes no response-time commitment.
