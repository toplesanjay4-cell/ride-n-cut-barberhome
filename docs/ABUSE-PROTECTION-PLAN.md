# Ride N Cut — Customer Abuse-Protection Plan

## Why this is a release blocker

Customer booking lookup currently accepts a WhatsApp number and a five-digit booking code. The customer browser calls Supabase RPCs directly for booking history and related quote, payment, and cancellation details. A five-digit code has a small search space, so the phone/code pair must not be treated as sufficient protection without durable attempt throttling.

The same concern applies to customer actions that authenticate with the same phone/code pair (quote approval, payment-method selection, cancellation requests, and payment-proof operations). Protecting only the visible history form would leave direct RPC calls available.

## Required design

1. **Put customer identity checks behind a server-side boundary.** Move phone/code-based history reads and state-changing customer actions behind Next.js Route Handlers. Do not rely on client-side cooldowns or hidden UI controls.
2. **Close direct bypasses.** After the server routes are in place, revoke anonymous/authenticated execution of the phone/code-based customer RPCs and grant execution only to the server's narrowly scoped database role. Verify every function signature and storage policy before changing grants. Do not use a service-role credential in browser code.
3. **Use durable shared rate-limit storage.** Use a private Supabase/Postgres counter table and an atomic SECURITY DEFINER RPC. The counter is shared across all Vercel instances and deployments; do not use an in-memory JavaScript Map.
4. **Use multiple independent keys.** HMAC of normalized client IP, using a server-only secret; HMAC of normalized phone number, using a different server-only secret; and an operation-specific key so lookup attempts cannot exhaust unrelated customer actions. Never persist raw phone numbers or raw IP addresses in the limiter.
5. **Return consistent responses.** Respond with HTTP 429 and a Retry-After header when a limit is reached. Avoid revealing whether a phone number, booking code, or booking exists. Apply a small response-time floor or equivalent mitigation if practical.
6. **Protect all relevant paths.** Include history lookup, quote/payment/cancellation detail reads, quote approval, payment selection, cancellation request, and proof upload/attachment. Review Storage upload/read policies separately; do not assume the API limiter covers direct Storage requests.
7. **Operational controls.** Make limits configurable, log only operation, outcome, and a non-reversible request identifier, and provide a safe way to tune limits after observing legitimate traffic. Do not log booking codes, full phone numbers, addresses, or payment proof contents.

## Initial acceptance criteria

- Requests from multiple Vercel instances share the same counters.
- Repeated invalid phone/code attempts are throttled by both IP and phone-derived keys.
- Changing the browser, refreshing, or calling Supabase directly cannot bypass the limits.
- All customer phone/code RPCs and proof-storage paths are covered or explicitly documented as a separate residual risk.
- Rate-limit storage failures fail closed for sensitive lookup/mutation operations, with a generic temporary-unavailable response.
- Automated tests cover threshold, window expiry, concurrent requests, malformed inputs, spoofed forwarding headers, 429/Retry-After, and store failure.
- A staging security test verifies direct anonymous RPC execution is denied after the migration.

## Safe implementation order

1. Apply the database rate-limit migration to a backed-up non-production Supabase project; configure a unique server-only HMAC secret in Vercel Preview.
2. Implement and test the shared limiter utility and server routes.
3. Switch the customer UI to those routes.
4. Add a reviewed SQL migration that removes direct public execution from the protected RPCs while preserving only the intended server execution path.
5. Review payment-proof Storage policies and test them independently.
6. Deploy to Preview, run automated and manual abuse tests, then apply the same reviewed migration and separately configured secrets to Production only after staging passes.

## Current status

The server API and database-backed rate-limit implementation have now been added to the redesign branch. The migration is not yet applied to any live database, so the new route intentionally remains unavailable until the migration and server-only secrets are configured in the target environment. The existing staging and production environments remain untouched.