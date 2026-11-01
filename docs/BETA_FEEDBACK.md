# In-app beta feedback

## Flow
Beta testers open Settings → Beta & diagnostics → Share Feedback. They select a category, write a message, and may explicitly provide an email address if they want a reply. The client includes app version, build number, beta channel and short Git SHA.

## Privacy and security
- The UI is available only for recognised non-production beta channels; production and UI-test builds do not expose it.
- The feedback endpoint accepts the public Supabase publishable key only as an API identifier. It is deployed with gateway JWT verification disabled and validates the key server-side.
- The endpoint hashes the platform-provided `cf-connecting-ip` value and uses an atomic server-side quota of 5 submissions/hour and 20/day. Raw IP addresses are never stored in the feedback tables. Missing platform address metadata fails closed.
- The Edge Function constructs an allowlisted row. Clients cannot read feedback or rate-limit rows; only the service role can access them. No account ID, device identifier, recipe content, screenshot, location, or diagnostics are collected.
- Contact email is optional and is stored only when the tester explicitly opts in. It is not used as an identity key.
- Feedback content is retained until manually actioned/deleted under the project's operational retention policy. Hashed rate-limit keys are cleaned daily after two inactive days.
- The UI warns testers not to include passwords, payment details, or third-party personal information.

## Deployment
1. Apply `supabase/migrations/20261031100000_beta_feedback.sql` to the `ate` Supabase project.
2. Deploy `supabase/functions/beta-feedback/index.ts` with JWT verification disabled (`--no-verify-jwt`).
3. Ensure the Edge Function has `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` and/or `ATE_PUBLIC_KEYS` configured. Never add the service-role key to the iOS app.
4. Verify missing/invalid API keys return 401, malformed and oversized payloads are rejected, quotas return 429, and valid beta submissions return 202.
5. Confirm `anon` and `authenticated` cannot select or insert into `beta_feedback` or access `beta_feedback_rate_limits`.
6. Submit a test report from a beta build and verify only the allowlisted fields appear in `public.beta_feedback`.

## Current scope
Screenshot/file attachments are deliberately not included in this first implementation. The app does not upload photos or local diagnostic logs. Add attachments only with a separate private-storage, consent, size-limit, retention and deletion design.

## Product lifecycle and feedback triage

Beta feedback is qualitative evidence for the Observe stage in the [Ate Product Lifecycle](../PRODUCT_LIFECYCLE.md). A submission is not automatically a validated finding or a product commitment. Triage themes, severity, build/cohort context and disposition; link resulting issues and decisions. Summarise interpreted themes in [OBSERVATION_REVIEWS/](../OBSERVATION_REVIEWS/) and connect them to the relevant outcome in [PRODUCT_OUTCOMES.md](../PRODUCT_OUTCOMES.md). Preserve the existing privacy and minimisation rules; do not copy unnecessary personal or sensitive content into review records.
