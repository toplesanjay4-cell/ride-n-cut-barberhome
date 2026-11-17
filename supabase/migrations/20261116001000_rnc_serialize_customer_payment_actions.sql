-- Serialize customer quote approval/payment selection/proof attachment against
-- cancellation and duplicate requests. Booking row is always locked first.
create or replace function public.customer_approve_booking_quote(
  p_phone text,
  p_code text,
  p_booking_id uuid,
  p_approval_channel text default 'website'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_status text;
  v_quote public.booking_price_quotes%rowtype;
begin
  if p_approval_channel not in ('website','whatsapp') then
    return false;
  end if;

  select b.status into v_booking_status
  from public.bookings b
  where b.id = p_booking_id
    and regexp_replace(coalesce(b.phone, ''), '[^0-9]', '', 'g') = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and b.booking_code::text = trim(p_code)
  for update;

  if not found or v_booking_status <> 'pending' then
    return false;
  end if;

  select * into v_quote
  from public.booking_price_quotes q
  where q.booking_id = p_booking_id
  order by q.quoted_at desc, q.id desc
  limit 1
  for update;

  if not found or v_quote.customer_approved_at is not null then
    return false;
  end if;

  update public.booking_price_quotes
  set customer_approved_at = now(), approval_channel = p_approval_channel
  where id = v_quote.id;

  update public.bookings
  set quoted_service_price = v_quote.service_price,
      travel_fee = v_quote.travel_fee,
      total_price = v_quote.total_price,
      price_approved_at = now(),
      price_approval_channel = p_approval_channel
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.customer_approve_booking_quote(text,text,uuid,text) from public;
grant execute on function public.customer_approve_booking_quote(text,text,uuid,text) to anon, authenticated;


create or replace function public.customer_select_booking_payment(
  p_phone text,
  p_code text,
  p_booking_id uuid,
  p_method text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_status text;
  v_quote public.booking_price_quotes%rowtype;
  v_payment public.booking_payments%rowtype;
  v_payment_status text;
begin
  if p_method not in ('cash','bank_transfer','e_wallet','qris') then
    return false;
  end if;

  if p_method <> 'cash' and not exists (
    select 1 from public.payment_methods pm
    where pm.method_type = p_method and pm.is_active = true
  ) then
    return false;
  end if;

  select b.status into v_booking_status
  from public.bookings b
  where b.id = p_booking_id
    and regexp_replace(coalesce(b.phone, ''), '[^0-9]', '', 'g') = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and b.booking_code::text = trim(p_code)
  for update;

  if not found or v_booking_status not in ('pending','confirmed') then
    return false;
  end if;

  select * into v_quote
  from public.booking_price_quotes q
  where q.booking_id = p_booking_id
  order by q.quoted_at desc, q.id desc
  limit 1
  for update;

  if not found or v_quote.customer_approved_at is null then
    return false;
  end if;

  select * into v_payment
  from public.booking_payments bp
  where bp.booking_id = p_booking_id
  order by bp.created_at desc, bp.id desc
  limit 1
  for update;

  if found then
    if v_payment.payment_status = 'paid'
       or v_payment.payment_status = 'refunded' then
      return false;
    end if;
    if v_payment.payment_status not in ('unpaid','waiting_verification','rejected') then
      return false;
    end if;

    v_payment_status := case when p_method = 'cash' then 'unpaid' else 'waiting_verification' end;

    update public.booking_payments
    set amount = v_quote.total_price,
        method_type = p_method,
        payment_status = v_payment_status,
        proof_url = null,
        updated_at = now()
    where id = v_payment.id;
  else
    v_payment_status := case when p_method = 'cash' then 'unpaid' else 'waiting_verification' end;
    insert into public.booking_payments(booking_id, amount, method_type, payment_status)
    values (p_booking_id, v_quote.total_price, p_method, v_payment_status);
  end if;

  update public.bookings
  set payment_method = p_method,
      payment_status = v_payment_status,
      payment_proof_url = null
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.customer_select_booking_payment(text,text,uuid,text) from public;
grant execute on function public.customer_select_booking_payment(text,text,uuid,text) to anon, authenticated;


create or replace function public.customer_attach_payment_proof(
  p_phone text,
  p_code text,
  p_booking_id uuid,
  p_proof_path text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_status text;
  v_phone_digits text;
  v_parts text[];
  v_payment public.booking_payments%rowtype;
begin
  if p_proof_path is null or length(p_proof_path) > 500 then
    return false;
  end if;

  v_parts := string_to_array(p_proof_path, '/');
  if cardinality(v_parts) <> 4
     or v_parts[1] <> p_booking_id::text
     or v_parts[2] <> trim(p_code)
     or v_parts[2] !~ '^[0-9]{5}$'
     or v_parts[3] !~ '^[0-9]{8,16}$'
     or v_parts[4] !~ '^[0-9]{10,16}-[A-Za-z0-9._-]{1,200}$' then
    return false;
  end if;

  select b.status, regexp_replace(coalesce(b.phone,''),'[^0-9]','','g')
    into v_booking_status, v_phone_digits
  from public.bookings b
  where b.id = p_booking_id
    and regexp_replace(coalesce(b.phone,''),'[^0-9]','','g') = regexp_replace(coalesce(p_phone,''),'[^0-9]','','g')
    and b.booking_code::text = trim(p_code)
  for update;

  if not found
     or v_booking_status not in ('pending','confirmed')
     or v_parts[3] <> v_phone_digits then
    return false;
  end if;

  select * into v_payment
  from public.booking_payments bp
  where bp.booking_id = p_booking_id
  order by bp.created_at desc, bp.id desc
  limit 1
  for update;

  if not found
     or v_payment.payment_status <> 'waiting_verification'
     or v_payment.method_type = 'cash' then
    return false;
  end if;

  -- Only attach a file that was actually uploaded to the private proof bucket.
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'rnc-payment-proofs'
      and o.name = p_proof_path
  ) then
    return false;
  end if;

  update public.booking_payments
  set proof_url = p_proof_path, updated_at = now()
  where id = v_payment.id;

  update public.bookings
  set payment_proof_url = p_proof_path
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.customer_attach_payment_proof(text,text,uuid,text) from public;
grant execute on function public.customer_attach_payment_proof(text,text,uuid,text) to anon, authenticated;
