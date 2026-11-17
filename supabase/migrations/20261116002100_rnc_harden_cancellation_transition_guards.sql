-- Close state-transition gaps while a customer cancellation is being reviewed.
-- Keep all writes inside the existing validated RPCs; no application rows are deleted.

-- Storage must not accept new proof uploads for a booking under cancellation review.
-- Only the latest payment row is eligible for a proof upload.
create or replace function public.rnc_can_upload_payment_proof(p_object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $rnc$
declare
  v_parts text[];
begin
  v_parts := storage.foldername(p_object_name);

  if coalesce(array_length(v_parts, 1), 0) <> 3
     or v_parts[1] !~* '^[0-9a-f-]{36}$'
     or v_parts[2] !~ '^[0-9]{5}$'
     or v_parts[3] !~ '^[0-9]{8,16}$' then
    return false;
  end if;

  return exists (
    select 1
    from public.bookings b
    where b.id::text = v_parts[1]
      and b.booking_code::text = v_parts[2]
      and regexp_replace(coalesce(b.phone, ''), '[^0-9]', '', 'g') = v_parts[3]
      and b.status in ('pending', 'confirmed')
      and coalesce(b.cancellation_status, 'none') <> 'requested'
      and exists (
        select 1
        from public.booking_payments bp
        where bp.id = (
          select bp_latest.id
          from public.booking_payments bp_latest
          where bp_latest.booking_id = b.id
          order by bp_latest.created_at desc, bp_latest.id desc
          limit 1
        )
          and bp.payment_status = 'waiting_verification'
          and bp.method_type <> 'cash'
      )
  );
end;
$rnc$;

revoke all on function public.rnc_can_upload_payment_proof(text) from public;
grant execute on function public.rnc_can_upload_payment_proof(text) to anon, authenticated;

comment on function public.rnc_can_upload_payment_proof(text) is
  'Allows proof upload only for the latest non-cash waiting-verification payment on an active booking with no cancellation request.';

-- A pending cancellation can only be resolved through the cancellation-review RPC.
-- A refund that has already been recorded cannot be reversed by rejecting the request.
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
  v_payment_status text;
begin
  if auth.uid() is null
     or not public.rnc_has_role(array['owner','staff'])
     or p_decision is null
     or p_decision not in ('approved','rejected') then
    return false;
  end if;

  select b.status, b.cancellation_status, b.payment_status
    into v_status, v_cancel_status, v_payment_status
  from public.bookings b
  where b.id = p_booking_id
  for update;

  if not found
     or v_status not in ('pending','confirmed')
     or v_cancel_status <> 'requested'
     or (p_decision = 'approved' and v_payment_status = 'paid')
     or (p_decision = 'rejected' and v_payment_status = 'refunded') then
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

-- Do not allow the generic status control to bypass a cancellation request.
-- Paid or refunded bookings must use the explicit cancellation/refund workflow.
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
  v_cancellation_status text;
  v_quote_approved timestamptz;
begin
  if auth.uid() is null or not public.rnc_has_role(array['owner','staff']) then
    return false;
  end if;

  if p_status is null or p_status not in ('confirmed','cancelled','completed') then
    return false;
  end if;

  select b.status, b.payment_status, b.cancellation_status
    into v_current_status, v_payment_status, v_cancellation_status
  from public.bookings b
  where b.id = p_booking_id
  for update;

  if not found or coalesce(v_cancellation_status, 'none') = 'requested' then
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
    if v_current_status not in ('pending','confirmed')
       or v_payment_status = 'paid'
       or v_payment_status = 'refunded' then
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
  'Owner/staff state transition guard: confirmation requires an approved quote; completion requires paid status; pending cancellation and paid/refunded cancellation must use the dedicated review workflow.';

-- A reschedule RPC also must not move a booking while cancellation is pending.
create or replace function public.rnc_guard_booking_schedule_update()
returns trigger
language plpgsql
set search_path = public
as $rnc$
begin
  if coalesce(old.cancellation_status, 'none') = 'requested'
     and (new.barber_id is distinct from old.barber_id
          or new.start_at is distinct from old.start_at
          or new.service_duration_minutes is distinct from old.service_duration_minutes) then
    raise exception 'Booking dengan permintaan pembatalan yang sedang ditinjau tidak dapat dijadwalkan ulang.';
  end if;

  if (new.barber_id is distinct from old.barber_id
      or new.start_at is distinct from old.start_at
      or new.service_duration_minutes is distinct from old.service_duration_minutes)
     and coalesce(current_setting('rnc.admin_reschedule', true), '') <> 'on' then
    raise exception 'Perubahan barber, waktu, atau durasi booking harus melalui proses reschedule tervalidasi.';
  end if;

  return new;
end;
$rnc$;

-- Refund must apply to the current payment record, not an obsolete historical row.
create or replace function public.rnc_admin_mark_payment_refunded(p_payment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_id uuid;
  v_payment_status text;
  v_booking_status text;
  v_cancellation_status text;
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

  -- Keep the lock order consistent with verification and customer payment RPCs.
  select b.status, b.cancellation_status
    into v_booking_status, v_cancellation_status
  from public.bookings b
  where b.id = v_booking_id
  for update;

  if not found
     or v_booking_status not in ('pending','confirmed')
     or v_cancellation_status <> 'requested' then
    return false;
  end if;

  select bp.payment_status into v_payment_status
  from public.booking_payments bp
  where bp.id = p_payment_id
    and bp.booking_id = v_booking_id
    and bp.id = (
      select bp_latest.id
      from public.booking_payments bp_latest
      where bp_latest.booking_id = v_booking_id
      order by bp_latest.created_at desc, bp_latest.id desc
      limit 1
    )
  for update;

  if not found or v_payment_status <> 'paid' then
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
  'Records a refund already completed outside the app, only for the latest payment on a booking with a pending cancellation request; it does not transfer funds.';
