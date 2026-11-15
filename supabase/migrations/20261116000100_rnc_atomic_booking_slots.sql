-- Atomically reserve a barber time slot so simultaneous customer requests cannot double-book.
-- Existing booking rows are preserved; this only adds an RPC and supporting index.

create index if not exists rnc_bookings_barber_start_idx
  on public.bookings (barber_id, start_at)
  where barber_id is not null;

create or replace function public.customer_create_booking(
  p_customer_name text,
  p_phone text,
  p_address text,
  p_barber_id uuid,
  p_start_at timestamptz,
  p_notes text,
  p_booking_code text,
  p_duration_minutes integer default 60
)
returns uuid
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking_id uuid;
  v_duration integer;
  v_buffer integer := 0;
begin
  if nullif(trim(p_customer_name), '') is null
     or length(trim(p_customer_name)) > 120
     or nullif(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'), '') is null
     or length(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')) not between 8 and 16
     or nullif(trim(p_address), '') is null
     or length(trim(p_address)) > 1000
     or p_barber_id is null
     or p_start_at is null
     or p_start_at <= now()
     or p_booking_code !~ '^[0-9]{5}$'
     or p_duration_minutes not between 10 and 480 then
    raise exception 'Data booking tidak valid.';
  end if;

  v_duration := p_duration_minutes;

  -- A transaction-scoped advisory lock serializes reservation attempts per barber.
  perform pg_advisory_xact_lock(hashtextextended(p_barber_id::text, 0));

  if not exists (select 1 from public.barbers b where b.id = p_barber_id) then
    raise exception 'Barber tidak ditemukan.';
  end if;

  select greatest(0, coalesce(ss.booking_buffer_minutes, 0))
    into v_buffer
  from public.site_settings ss
  order by ss.id
  limit 1;
  v_buffer := coalesce(v_buffer, 0);

  if exists (
    select 1
    from public.bookings b
    where b.barber_id = p_barber_id
      and lower(coalesce(b.status, '')) not in ('cancelled', 'canceled')
      and b.start_at < p_start_at + make_interval(mins => v_duration + v_buffer)
      and b.start_at + make_interval(mins => greatest(10, coalesce(b.service_duration_minutes, 60)) + v_buffer) > p_start_at
  ) then
    raise exception 'Jadwal barber tersebut baru saja terisi. Silakan pilih jam lain.';
  end if;

  insert into public.bookings (
    customer_name, phone, address, barber_id, start_at, notes,
    status, booking_code, service_duration_minutes
  ) values (
    trim(p_customer_name),
    trim(p_phone),
    trim(p_address),
    p_barber_id,
    p_start_at,
    nullif(trim(coalesce(p_notes, '')), ''),
    'pending',
    p_booking_code,
    v_duration
  )
  returning id into v_booking_id;

  return v_booking_id;
end;
$rnc$;

revoke all on function public.customer_create_booking(text,text,text,uuid,timestamptz,text,text,integer) from public;
grant execute on function public.customer_create_booking(text,text,text,uuid,timestamptz,text,text,integer) to anon, authenticated;
