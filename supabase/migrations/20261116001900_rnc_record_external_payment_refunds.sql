-- Record a refund only after the owner/staff has actually returned the money
-- through the external bank, e-wallet, or cash process.
alter table public.booking_payments
  add column if not exists refunded_at timestamptz,
  add column if not exists refund_recorded_by uuid references auth.users(id) on delete set null;

create or replace function public.rnc_admin_mark_payment_refunded(p_payment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_id uuid;
  v_payment_status text;
begin
  if auth.uid() is null or not public.rnc_has_role(array['owner','staff']) then
    return false;
  end if;

  select bp.booking_id, bp.payment_status
    into v_booking_id, v_payment_status
  from public.booking_payments bp
  where bp.id = p_payment_id
  for update;

  if not found or v_payment_status <> 'paid' then
    return false;
  end if;

  perform 1
  from public.bookings b
  where b.id = v_booking_id
  for update;

  if not found then
    return false;
  end if;

  update public.booking_payments
  set payment_status = 'refunded',
      refunded_at = now(),
      refund_recorded_by = auth.uid(),
      updated_at = now()
  where id = p_payment_id;

  update public.bookings
  set payment_status = 'refunded'
  where id = v_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.rnc_admin_mark_payment_refunded(uuid) from public;
grant execute on function public.rnc_admin_mark_payment_refunded(uuid) to authenticated;

comment on function public.rnc_admin_mark_payment_refunded(uuid) is
  'Records a refund after money has actually been returned outside the app; it does not transfer funds.';
