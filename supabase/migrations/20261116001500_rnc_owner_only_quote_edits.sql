-- Price quotes are owner-controlled. Customer approval remains through
-- the security-definer customer_approve_booking_quote RPC.
drop policy if exists "rnc staff updates quotes" on public.booking_price_quotes;
drop policy if exists "rnc owner updates quotes" on public.booking_price_quotes;

create policy "rnc owner updates quotes"
  on public.booking_price_quotes
  for update
  to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

comment on policy "rnc owner updates quotes" on public.booking_price_quotes is
  'Only owners may edit price quote fields; customer approval is recorded through the validated customer RPC.';
