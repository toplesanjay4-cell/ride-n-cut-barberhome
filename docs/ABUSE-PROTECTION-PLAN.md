# Ride N Cut — Customer Abuse-Protection Plan

## Threat model

Customer history and follow-up actions use a WhatsApp number plus a five-digit booking code. That pair must not be treated as sufficient protection without durable throttling. The protected operations are history lookup, quote/payment/cancellation detail reads, quote approval, payment selection, cancellation requests, and payment-proof upload/attachment.

## Implemented on the redesign branch

- Phone/code operations are routed through `POST /api/customer/booking`; the customer UI does not call those protected RPCs directly.
- The `20261119000100_rnc_rate_limit_customer_access.sql` migration revokes anonymous/authenticated execution of the protected RPC overloads and grants them to `service_role` only.
- A private Postgres counter table and atomic SECURITY DEFINER RPC share counters across application instances. Raw phone numbers and IP addresses are not stored.
- The route derives separate, operation-scoped IP and phone keys with HMAC-SHA256. Both use the same server-only secret with distinct `ip:` and `phone:` domain prefixes; this provides key separation without storing either input.
- Current route limits are: lookup 30/IP and 5/phone per 15 minutes; other actions 40/IP and 10/phone per 15 minutes; proof upload 20/IP and 4/phone per hour.
- Rate-limit configuration failures fail closed with a generic 503. Exceeded limits return 429 and `Retry-After`.
- Customer proof upload is handled by the server route; the migration removes the previous customer Storage upload policy. The proof bucket remains private and admins use short-lived signed URLs.
- The route checks the claimed MIME type against the file's leading JPEG, PNG, WEBP, or PDF signature before upload. This is format validation only; it is not malware scanning or PDF sanitization.

The migration and route are committed to this branch, but the migration has **not** been applied to a live database. The route therefore remains unavailable until the target environment has the migration, `SUPABASE_SERVICE_ROLE_KEY`, and a unique `RNC_RATE_LIMIT_HMAC_SECRET` configured.

## Remaining verification

- Apply all migrations to a backed-up non-production Supabase project and run `supabase/tests/rnc_security_smoke_test.sql` as documented.
- Verify direct anonymous/authenticated execution is denied for every protected RPC overload, while the server role can execute them.
- In production, `requestIp()` trusts only a syntactically valid, single-address `x-forwarded-for` value. Vercel documents that it overwrites this header to prevent IP spoofing. The route deliberately ignores `x-real-ip` and `x-vercel-forwarded-for`; if the trusted header is absent or malformed, it fails closed with 503. Development uses a fixed loopback identity. Unit tests cover spoofed fallback headers, malformed values, IPv4, IPv6, and development behavior.
- Verify the `x-forwarded-for` value in Preview through the actual hosting path. When another proxy sits in front of Vercel, Vercel may report the proxy's address instead of the end user's address; this is safer than trusting a client-controlled fallback but may reduce per-IP rate-limit accuracy. Do not restore untrusted fallbacks.
- Add route/integration tests for IP and phone thresholds, window expiry, concurrent requests, malformed rate-limit responses, 429/`Retry-After`, and database/secret failure.
- Test Storage policies independently: customers must not upload directly, the server can upload, the bucket stays private, and only authorized admins can obtain signed read URLs.
- Observe legitimate traffic before changing the current hard-coded per-action limits. Do not log booking codes, full phone numbers, addresses, IP addresses, or proof contents.

## Safe rollout order

1. Back up a **non-production** Supabase project.
2. Apply the 25 ordered migrations there, verify the existing owner UUID, and run the read-only security smoke test.
3. Configure a unique server-only HMAC secret and service-role key in Vercel Preview; never expose either through a `NEXT_PUBLIC_` variable or commit a real value.
4. Verify proxy IP handling, rate-limit behavior, protected RPC grants, Storage policies, and the complete customer/admin flows in Preview.
5. Only after staging checks pass, plan a separately reviewed production backup and migration window. No production migration or deployment is authorized by this branch work.

## Release status

The branch contains the rate-limit migration and server-side route, but neither has been validated against a real Supabase/Vercel staging environment. The security smoke test is read-only and has not yet been executed against staging. This feature remains a release blocker until those checks pass.
