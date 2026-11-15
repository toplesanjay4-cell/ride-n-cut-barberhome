# Ride N Cut redesign — safe setup

This redesign is being developed on `redesign/ride-n-cut-overhaul`. Do not deploy it to production until the migration, owner role, environment, and end-to-end booking tests have passed.

## Important data-safety notes

- The SQL migration is additive. It does not delete, rename, or rewrite existing `bookings`, `barbers`, or `site_settings` rows.
- Take a Supabase database backup before applying any migration.
- Existing bookings remain in the legacy booking flow until the new workflow is deliberately enabled.
- Do not expose a Supabase service-role key in browser code or public environment variables.

## Apply the new schema

1. Open the correct Supabase project for Ride N Cut.
2. Create/download a database backup first.
3. Open SQL Editor and run `supabase/migrations/20261115000100_rnc_redesign_additive_schema.sql`.
4. Verify the new tables exist: `user_roles`, `services`, `payment_methods`, `booking_price_quotes`, `booking_payments`, `expense_categories`, and `expenses`.
5. Verify the new nullable/defaulted columns on `bookings` and `site_settings`.
6. Verify the private Storage bucket `rnc-payment-proofs` exists, with a 5 MB limit and image/PDF MIME restrictions. The migration adds upload/read policies tied to booking ID, booking code, and phone number.

## Bootstrap the owner role

The first owner cannot be self-assigned through the public website. After confirming the existing admin login email in Supabase Authentication:

1. Find that user's UUID in Supabase Authentication → Users.
2. In SQL Editor, run this statement with the verified UUID and a display name:

```sql
insert into public.user_roles (user_id, role, display_name)
values ('REPLACE-WITH-EXISTING-ADMIN-USER-UUID', 'owner', 'Ride N Cut Owner')
on conflict (user_id) do update
set role = 'owner', is_active = true, display_name = excluded.display_name;
```

Do not guess the UUID. This step preserves the existing Auth account and password.

## Owner and staff access\n\n- The admin UI checks the signed-in user against `user_roles`; accounts without an active role are denied dashboard access.\n- Only the owner sees Website and Staff management tabs. Staff accounts are created through `POST /api/admin/staff`, which validates the caller with Supabase Auth and checks the active owner role server-side before using the service-role client.\n- Configure `SUPABASE_SERVICE_ROLE_KEY` as a server-only Vercel environment variable for the redesign deployment. Never prefix it with `NEXT_PUBLIC_`, commit it, or expose it in browser code.\n- The owner must first be bootstrapped manually using the SQL above. Staff passwords are created by the owner and should be shared securely and changed after first login.\n- Staff access is still partial: verify every underlying table policy and test unauthorized requests in staging; hiding a UI tab is not a substitute for database RLS.\n\n## Payment workflow status

- Customers can select cash, bank transfer, e-wallet, or QRIS after accepting the quote.
- For non-cash payments, customers can upload a JPG, PNG, WEBP, or PDF proof (maximum 5 MB) to the private `rnc-payment-proofs` bucket.
- Admins can view the proof through a short-lived signed URL and manually verify receipt.
- A transfer is not marked paid until an admin verifies it. Cash remains unpaid until the admin records receipt.
- The customer page reads active payment method details from `payment_methods`; verify bank/e-wallet/QRIS details and QR image URLs in staging before public launch.
- The admin finance tab now supports date-filtered expense entry and a preliminary revenue-minus-expense view. Revenue is counted only for completed bookings with a recorded paid payment.
- Staff can read, add, and update expenses; only owners can delete expenses and manage custom expense categories. Verify these policies in a staging Supabase project before use.

## Current implementation boundary

The quote approval and payment UI is now partially implemented on the redesign branch: admin quote entry, customer approval, payment method selection, private proof upload, and manual payment verification. It is not production-ready until the SQL migration is reviewed/applied in a non-production Supabase project and end-to-end tests pass. The owner staff-account creation UI and server-side owner check are partially implemented. Full least-privilege RLS verification, map routing and distance fees, calendar conflict logic with service durations/buffers, complete finance reporting, automated backups, and end-to-end tests are still incomplete.

## Free map option

The planned map base is OpenStreetMap. Public geocoding/routing endpoints have fair-use limits and are not guaranteed as unlimited production infrastructure. For production traffic, review the current usage policies and consider a self-hosted or appropriately provisioned routing/geocoding service.
