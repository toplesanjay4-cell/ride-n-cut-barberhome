-- Close a race between booking cancellation and payment verification.
-- Lock both rows in the same transaction and reject blank proof paths.
create or replace function public.rnc_admin_verify_booking_payment(p_payment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_id uuid;
  v_method text;
  v_status text;
  v_proof text;
  v_booking_status text;
begin
  if auth.uid() is null or not public.rnc_has_role(array['owner','staff']) then
    return false;
  end if;

  select bp.booking_id into v_booking_id
  from public.booking_payments bp
  where bp.id = p_payment_id;

  if not found then
    return false;
  end if;

  -- Always lock booking first, then payment, matching customer and refund RPCs.
  select b.status into v_booking_status
  from public.bookings b
  where b.id = v_booking_id
  for update;

  if not found or lower(coalesce(v_booking_status, '')) in ('cancelled', 'canceled') then
    return false;
  end if;

  select bp.method_type, bp.payment_status, bp.proof_url
    into v_method, v_status, v_proof
  from public.booking_payments bp
  where bp.id = p_payment_id and bp.booking_id = v_booking_id
  for update;

  if not found or v_status = 'paid' or v_status = 'refunded' then
    return false;
  end if;

  if v_method = 'cash' then
    if v_status <> 'unpaid' then
      return false;
    end if;
  else
    if v_status <> 'waiting_verification'
       or nullif(btrim(v_proof), '') is null then
      return false;
    end if;
  end if;

  update public.booking_payments
  set payment_status = 'paid',
      received_at = now(),
      verified_by = auth.uid(),
      updated_at = now()
  where id = p_payment_id;

  update public.bookings
  set payment_status = 'paid'
  where id = v_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.rnc_admin_verify_booking_payment(uuid) from public;
grant execute on function public.rnc_admin_verify_booking_payment(uuid) to authenticated;
