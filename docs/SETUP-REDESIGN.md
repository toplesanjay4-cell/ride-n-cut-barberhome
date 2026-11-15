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
4. Run the remaining migrations in filename order: `20261116000100_rnc_atomic_booking_slots.sql`, `20261116000200_rnc_service_duration_booking.sql`, `20261116000300_rnc_booking_horizon_guard.sql`, `20261116000400_rnc_lock_payment_writes.sql`, and `20261116000500_rnc_validate_payment_verification.sql`.
5. Verify the new tables exist: `user_roles`, `services`, `payment_methods`, `booking_price_quotes`, `booking_payments`, `expense_categories`, and `expenses`.
6. Verify the new nullable/defaulted columns on `bookings` and `site_settings`.
7. Verify the private Storage bucket `rnc-payment-proofs` exists, with a 5 MB limit and image/PDF MIME restrictions. The migration adds upload/read policies tied to booking ID, booking code, and phone number.

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

## Owner and staff access

- The admin UI checks the signed-in user against `user_roles`; accounts without an active role are denied dashboard access.
- Only the owner sees Website and Staff management tabs. Staff accounts are created through `POST /api/admin/staff`, which validates the caller with Supabase Auth and checks the active owner role server-side before using the service-role client.
- Configure `SUPABASE_SERVICE_ROLE_KEY` as a server-only Vercel environment variable for the redesign deployment. Never prefix it with `NEXT_PUBLIC_`, commit it, or expose it in browser code.
- The owner must first be bootstrapped manually using the SQL above. Staff passwords are created by the owner and should be shared securely and changed after first login.
- Staff access is implemented in the admin UI and core additive-table policies, but still requires direct unauthorized API/RLS tests in staging; hiding a UI tab is not a substitute for database RLS.

## Payment workflow status

- Customers can select cash, bank transfer, e-wallet, or QRIS after accepting the quote.
- For non-cash payments, customers can upload a JPG, PNG, WEBP, or PDF proof (maximum 5 MB) to the private `rnc-payment-proofs` bucket.
- Admins can view the proof through a short-lived signed URL and manually verify receipt.
- A transfer is not marked paid until an admin verifies it. Cash remains unpaid until the admin records receipt.
- The customer page reads active payment method details from `payment_methods`; verify bank/e-wallet/QRIS details and QR image URLs in staging before public launch.
- The admin finance tab supports date-filtered expense entry, revenue-minus-expense reporting, CSV/PDF export, and booking analytics. Revenue is counted only for completed bookings with a recorded paid payment.
- Staff can read, add, and update expenses; only owners can delete expenses and manage custom expense categories. Verify these policies in a staging Supabase project before use.

## Current implementation boundary

The redesign branch now includes the customer booking flow, admin booking management, owner/staff role UI, service management, calendar day/week/month views, quote approval, payment method selection, private proof upload, manual payment verification, finance summaries, CSV/PDF exports, and booking analytics. The database checks barber-slot conflicts atomically, derives active service durations, enforces a configurable 1–30 day booking horizon (14 days by default), and blocks direct client writes to payment records and quote approvals, and validates booking/payment state before staff can record receipt.

This is still a staging candidate, not a production release. Before merging or deploying, apply all migrations to a non-production Supabase project after taking a backup, verify the existing owner UUID, test owner/staff RLS directly, test booking/payment flows end-to-end, and confirm the Vercel environment variables. Interactive customer map-pin selection and route-distance estimation, automated off-site backups, abuse/rate limiting for public booking lookup, and a complete end-to-end test suite remain outstanding.

## Free map option

The planned map base is OpenStreetMap. Public geocoding/routing endpoints have fair-use limits and are not guaranteed as unlimited production infrastructure. For production traffic, review the current usage policies and consider a self-hosted or appropriately provisioned routing/geocoding service.
