# Security and vulnerability disclosure

_Last updated: 11 October 2026_

## How ate protects data
- HTTPS for all connections; passwords hashed by Supabase Auth.
- Row-level security: each account can only read its own synced data. Shared recipes are read-only and public by design.
- Account deletion and sharing run through server functions that check your sign-in.
- Health data, AI processing and widget data never leave the device.

## Reporting a vulnerability
Email **melusi.l.k@gmail.com** with the subject **"Security"**. Please include steps to reproduce, the build number and the impact.

**Please do:** test only with your own account and data, give me reasonable time to fix (I aim for 90 days), and keep it private until it's fixed.
**Please don't:** access other people's data, run denial-of-service or spam, or use social engineering.

I won't take legal action against good-faith research that follows these rules. I'll confirm your report within 5 working days, and credit you here if you want. There's no paid bounty.

## security.txt
A `/.well-known/security.txt` file only works at the root of a domain. This site lives at `melusi-k.github.io/ate-legal/`, so it can't have one yet. Once ate has a custom domain, one will be published there pointing to this page.
