-- Validate the payment's current state and booking state before recording receipt.
-- Cash is verified from unpaid; non-cash requires a submitted proof awaiting review.
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
  if not public.rnc_has_role(array['owner','staff']) then
    return false;
  end if;

  select bp.booking_id, bp.method_type, bp.payment_status, bp.proof_url, b.status
    into v_booking_id, v_method, v_status, v_proof, v_booking_status
  from public.booking_payments bp
  join public.bookings b on b.id = bp.booking_id
  where bp.id = p_payment_id
  for update of bp;

  if not found
     or lower(coalesce(v_booking_status, '')) in ('cancelled', 'canceled')
     or v_status = 'paid' then
    return false;
  end if;

  if v_method = 'cash' then
    if v_status <> 'unpaid' then
      return false;
    end if;
  else
    if v_status <> 'waiting_verification' or v_proof is null then
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
