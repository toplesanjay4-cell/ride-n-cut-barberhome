-- Price quotes are owner-controlled. Staff may view quotes but cannot create or edit prices.
-- Customer approval remains through the security-definer customer_approve_booking_quote RPC.
drop policy if exists "rnc staff creates quotes" on public.booking_price_quotes;
drop policy if exists "rnc owner creates quotes" on public.booking_price_quotes;
create policy "rnc owner creates quotes"
  on public.booking_price_quotes
  for insert
  to authenticated
  with check (public.rnc_has_role(array['owner']));

drop policy if exists "rnc staff updates quotes" on public.booking_price_quotes;
drop policy if exists "rnc owner updates quotes" on public.booking_price_quotes;
create policy "rnc owner updates quotes"
  on public.booking_price_quotes
  for update
  to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

comment on policy "rnc owner creates quotes" on public.booking_price_quotes is
  'Only owners may create price quotes; staff may not set customer prices.';
comment on policy "rnc owner updates quotes" on public.booking_price_quotes is
  'Only owners may edit price quote fields; customer approval is recorded through the validated customer RPC.';
