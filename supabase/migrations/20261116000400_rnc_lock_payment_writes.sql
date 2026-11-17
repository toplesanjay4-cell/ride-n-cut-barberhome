-- Keep payment state transitions behind the SECURITY DEFINER RPCs.
-- Admin UI reads payment rows and calls rnc_admin_verify_booking_payment;
-- customers use customer_select_booking_payment/customer_attach_payment_proof.
-- Direct table writes would otherwise let an authenticated client mark a transfer paid.
revoke insert, update, delete on table public.booking_payments from anon, authenticated;

-- Quotes are append-only from the dashboard. Customer approval is recorded only
-- through customer_approve_booking_quote, which validates phone + booking code.
revoke update, delete on table public.booking_price_quotes from anon, authenticated;

comment on table public.booking_payments is
  'Payment records are read by authenticated staff; mutations must use validated SECURITY DEFINER RPCs.';
comment on table public.booking_price_quotes is
  'Price quotes are append-only for dashboard users; customer approval must use the validated RPC.';
