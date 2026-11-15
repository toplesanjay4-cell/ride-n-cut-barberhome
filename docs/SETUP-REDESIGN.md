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

## Payment workflow status

- Customers can select cash, bank transfer, e-wallet, or QRIS after accepting the quote.
- For non-cash payments, customers can upload a JPG, PNG, WEBP, or PDF proof (maximum 5 MB) to the private `rnc-payment-proofs` bucket.
- Admins can view the proof through a short-lived signed URL and manually verify receipt.
- A transfer is not marked paid until an admin verifies it. Cash remains unpaid until the admin records receipt.
- The current UI does not yet load payment method account details from the configurable `payment_methods` table; add and test those settings before public launch.

## Current implementation boundary

The schema is groundwork, not a completed feature. It does not by itself provide the full owner/staff UI, price approval screens, payment proof storage, map routing, calendar conflict logic, or scheduled backups. Those require application code, storage bucket policies, and deployment configuration. Do not announce these features as live until tested.

## Free map option

The planned map base is OpenStreetMap. Public geocoding/routing endpoints have fair-use limits and are not guaranteed as unlimited production infrastructure. For production traffic, review the current usage policies and consider a self-hosted or appropriately provisioned routing/geocoding service.
