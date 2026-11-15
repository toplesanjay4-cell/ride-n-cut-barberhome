-- Enforce owner-only control of website settings and customer price quotes.
-- Staff can continue operating bookings and payments, but cannot change prices.
alter table public.site_settings enable row level security;

drop policy if exists "rnc owner only site settings" on public.site_settings;
create policy "rnc owner only site settings"
  on public.site_settings
  as restrictive
  for all
  to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

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
