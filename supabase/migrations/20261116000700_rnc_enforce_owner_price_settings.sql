-- Enforce owner-only control of website settings and customer price quotes.
-- Staff can continue operating bookings and payments, but cannot change prices.
alter table public.site_settings enable row level security;

-- Keep the public booking page able to read its public-facing settings after RLS is enabled.
drop policy if exists "rnc public reads site settings" on public.site_settings;
create policy "rnc public reads site settings"
  on public.site_settings
  for select
  to anon, authenticated
  using (true);

-- RLS requires a permissive policy as well as the restrictive owner guard below.
drop policy if exists "rnc owner manages site settings" on public.site_settings;
create policy "rnc owner manages site settings"
  on public.site_settings
  for all
  to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

-- Restrict writes only. Staff still need SELECT access to public schedule
-- settings used by the admin calendar and booking workflow.
drop policy if exists "rnc owner only site settings" on public.site_settings;
drop policy if exists "rnc owner only updates site settings" on public.site_settings;
drop policy if exists "rnc owner only inserts site settings" on public.site_settings;
drop policy if exists "rnc owner only deletes site settings" on public.site_settings;

create policy "rnc owner only updates site settings"
  on public.site_settings as restrictive
  for update to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create policy "rnc owner only inserts site settings"
  on public.site_settings as restrictive
  for insert to authenticated
  with check (public.rnc_has_role(array['owner']));

create policy "rnc owner only deletes site settings"
  on public.site_settings as restrictive
  for delete to authenticated
  using (public.rnc_has_role(array['owner']));

drop policy if exists "rnc staff creates quotes" on public.booking_price_quotes;
drop policy if exists "rnc owner creates quotes" on public.booking_price_quotes;
create policy "rnc owner creates quotes"
  on public.booking_price_quotes
  for insert
  to authenticated
  with check (public.rnc_has_role(array['owner']));

comment on policy "rnc owner only site settings" on public.site_settings is
  'Restrictive guard: staff cannot change owner-controlled website and booking settings.';
comment on policy "rnc owner creates quotes" on public.booking_price_quotes is
  'Only owners may create or change per-booking price quotes.';
