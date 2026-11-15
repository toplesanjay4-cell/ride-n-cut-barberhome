-- Customer cancellation is a request; only an authenticated admin can approve it.
alter table public.bookings
  add column if not exists cancellation_status text not null default 'none'
  check (cancellation_status in ('none','requested','approved','rejected'));

create or replace function public.customer_request_booking_cancellation(
  p_phone text,
  p_code text,
  p_booking_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_status text;
  v_cancel_status text;
begin
  select b.status, b.cancellation_status
    into v_status, v_cancel_status
  from public.bookings b
  where b.id = p_booking_id
    and regexp_replace(coalesce(b.phone,''),'[^0-9]','','g') = regexp_replace(coalesce(p_phone,''),'[^0-9]','','g')
    and b.booking_code::text = trim(p_code)
  for update;

  if not found
     or v_status not in ('pending','confirmed')
     or coalesce(v_cancel_status,'none') = 'requested' then
    return false;
  end if;

  update public.bookings
  set cancellation_requested_at = now(),
      cancellation_reviewed_at = null,
      cancellation_status = 'requested'
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.customer_request_booking_cancellation(text,text,uuid) from public;
grant execute on function public.customer_request_booking_cancellation(text,text,uuid) to anon, authenticated;


create or replace function public.rnc_admin_review_booking_cancellation(
  p_booking_id uuid,
  p_decision text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_status text;
  v_cancel_status text;
begin
  if auth.uid() is null
     or not public.rnc_has_role(array['owner','staff'])
     or p_decision is null
     or p_decision not in ('approved','rejected') then
    return false;
  end if;

  select b.status, b.cancellation_status
    into v_status, v_cancel_status
  from public.bookings b
  where b.id = p_booking_id
  for update;

  if not found
     or v_status not in ('pending','confirmed')
     or v_cancel_status <> 'requested' then
    return false;
  end if;

  update public.bookings
  set status = case when p_decision = 'approved' then 'cancelled' else status end,
      cancellation_status = p_decision,
      cancellation_reviewed_at = now()
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.rnc_admin_review_booking_cancellation(uuid,text) from public;
grant execute on function public.rnc_admin_review_booking_cancellation(uuid,text) to authenticated;


create or replace function public.customer_booking_cancellation_status(
  p_phone text,
  p_code text,
  p_booking_id uuid
)
returns table (
  cancellation_status text,
  cancellation_requested_at timestamptz,
  cancellation_reviewed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $rnc$
  select coalesce(b.cancellation_status,'none'),
         b.cancellation_requested_at,
         b.cancellation_reviewed_at
  from public.bookings b
  where b.id = p_booking_id
    and regexp_replace(coalesce(b.phone,''),'[^0-9]','','g') = regexp_replace(coalesce(p_phone,''),'[^0-9]','','g')
    and b.booking_code::text = trim(p_code)
  limit 1;
$rnc$;

revoke all on function public.customer_booking_cancellation_status(text,text,uuid) from public;
grant execute on function public.customer_booking_cancellation_status(text,text,uuid) to anon, authenticated;
