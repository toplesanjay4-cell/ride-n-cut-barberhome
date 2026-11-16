-- Prevent direct PostgREST updates from bypassing booking state/payment RPCs.
-- Security-definer RPCs owned by postgres remain the only application write path
-- for these protected columns. Ordinary booking details remain editable via the
-- separately validated admin reschedule workflow.
create or replace function public.rnc_guard_booking_state_update()
returns trigger
language plpgsql
set search_path = public
as $rnc$
begin
  if (
    new.status is distinct from old.status
    or new.payment_status is distinct from old.payment_status
    or new.payment_method is distinct from old.payment_method
    or new.payment_proof_url is distinct from old.payment_proof_url
    or new.quoted_service_price is distinct from old.quoted_service_price
    or new.travel_fee is distinct from old.travel_fee
    or new.total_price is distinct from old.total_price
    or new.price_approved_at is distinct from old.price_approved_at
    or new.price_approval_channel is distinct from old.price_approval_channel
    or new.cancellation_status is distinct from old.cancellation_status
    or new.cancellation_requested_at is distinct from old.cancellation_requested_at
    or new.cancellation_reviewed_at is distinct from old.cancellation_reviewed_at
  ) and current_user <> 'postgres' then
    raise exception 'Perubahan status, pembayaran, penawaran, dan pembatalan harus melalui RPC tervalidasi.';
  end if;

  return new;
end;
$rnc$;

drop trigger if exists rnc_guard_booking_state_update on public.bookings;
create trigger rnc_guard_booking_state_update
before update of
  status,
  payment_status,
  payment_method,
  payment_proof_url,
  quoted_service_price,
  travel_fee,
  total_price,
  price_approved_at,
  price_approval_channel,
  cancellation_status,
  cancellation_requested_at,
  cancellation_reviewed_at
on public.bookings
for each row
execute function public.rnc_guard_booking_state_update();

comment on function public.rnc_guard_booking_state_update() is
  'Blocks direct API writes to booking status, quote, payment, and cancellation state; application changes must pass through SECURITY DEFINER validation RPCs owned by postgres.';
