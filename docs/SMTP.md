# Custom SMTP for ate auth emails (fixes "Email limit reached")

Supabase's built-in mailer sends only ~2–4 auth emails per hour per project and is meant for testing. Beta testers hit it on sign-up, magic link and password reset (A-AUTH-02 / A-AUTH-05). The fix is a real SMTP provider.

**Needs from Melusi:** a provider account and its API key (not in this repo, never in the app).

## Resend (free tier: 3,000 emails/month, 100/day)
1. Sign up at https://resend.com → **Domains** → add a domain you control (or use `onboarding@resend.dev` for testing only, which sends to your own address only).
2. Add the DNS records Resend shows (SPF/DKIM) and wait for "Verified".
3. **API Keys** → create a key with "Sending access".
4. Supabase dashboard → project `ploncuhexmwydjxljuhe` → **Authentication › Emails › SMTP Settings** → enable custom SMTP:
   - Host `smtp.resend.com`, port `465`, username `resend`, password = the API key
   - Sender email `no-reply@<your domain>`, sender name `ate`
   (or via the Management API: `PATCH /v1/projects/ploncuhexmwydjxljuhe/config/auth` with `smtp_host`, `smtp_port`, `smtp_user`, `smtp_pass`, `smtp_admin_email`, `smtp_sender_name`.)
5. Then raise the limit: `PATCH …/config/auth` with `{"rate_limit_email_sent": 30}` (per hour). This is refused/ineffective until custom SMTP is on.
6. Send a test reset from ate; check it arrives within a minute.

Until then the app shows "Email limit reached — try again in about an hour" with a countdown, instead of "wait a minute".
