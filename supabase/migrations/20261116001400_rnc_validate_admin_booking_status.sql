-- Guard administrative booking state changes in one database transaction.
-- Booking history is retained; there is deliberately no hard-delete workflow.
create or replace function public.rnc_admin_set_booking_status(
  p_booking_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_current_status text;
  v_payment_status text;
  v_quote_approved timestamptz;
begin
  if not public.rnc_has_role(array['owner','staff']) then
    return false;
  end if;

  if p_status not in ('confirmed','cancelled','completed') then
    return false;
  end if;

  select b.status, b.payment_status
    into v_current_status, v_payment_status
  from public.bookings b
  where b.id = p_booking_id
  for update;

  if not found then
    return false;
  end if;

  if v_current_status not in ('pending','confirmed','cancelled') then
    return false;
  end if;

  if p_status = 'confirmed' then
    if v_current_status <> 'pending' then
      return false;
    end if;
    select q.customer_approved_at into v_quote_approved
    from public.booking_price_quotes q
    where q.booking_id = p_booking_id
    order by q.quoted_at desc, q.id desc
    limit 1;
    if v_quote_approved is null then
      return false;
    end if;
  elsif p_status = 'completed' then
    if v_current_status <> 'confirmed' or v_payment_status <> 'paid' then
      return false;
    end if;
  elsif p_status = 'cancelled' then
    if v_current_status not in ('pending','confirmed') then
      return false;
    end if;
  end if;

  update public.bookings
  set status = p_status
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.rnc_admin_set_booking_status(uuid,text) from public;
grant execute on function public.rnc_admin_set_booking_status(uuid,text) to authenticated;

comment on function public.rnc_admin_set_booking_status(uuid,text) is
  'Owner/staff state transition guard: confirmation requires approved quote; completion requires confirmed booking and paid payment. Booking history is retained.';
