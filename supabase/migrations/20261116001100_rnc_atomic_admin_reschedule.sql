-- Validate admin rescheduling atomically, using the same per-barber advisory lock
-- as customer booking creation. Existing booking data is preserved.
create or replace function public.rnc_admin_update_booking(
  p_booking_id uuid,
  p_customer_name text,
  p_phone text,
  p_address text,
  p_barber_id uuid,
  p_start_at timestamptz,
  p_notes text,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_booking public.bookings%rowtype;
  v_duration integer;
  v_buffer integer := 0;
begin
  if auth.uid() is null
     or not public.rnc_has_role(array['owner','staff']) then
    raise exception 'Akses admin diperlukan.';
  end if;

  if p_booking_id is null
     or nullif(trim(p_customer_name), '') is null
     or length(trim(p_customer_name)) > 120
     or length(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')) not between 8 and 16
     or nullif(trim(p_address), '') is null
     or length(trim(p_address)) > 1000
     or p_barber_id is null
     or p_start_at is null
     or p_status not in ('pending','confirmed','completed','cancelled') then
    raise exception 'Data perubahan booking tidak valid.';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking tidak ditemukan.';
  end if;

  if lower(coalesce(v_booking.status, '')) in ('cancelled','canceled','completed') then
    raise exception 'Booking yang sudah selesai atau dibatalkan tidak dapat diedit.';
  end if;

  if not exists (
    select 1 from public.barbers b
    where b.id = p_barber_id and b.is_active = true
  ) then
    raise exception 'Pilih barber yang masih aktif.';
  end if;

  v_duration := greatest(10, least(480, coalesce(v_booking.service_duration_minutes, 60)));

  -- Same lock key as customer_create_booking: all reservations for this barber serialize.
  perform pg_advisory_xact_lock(hashtextextended(p_barber_id::text, 0));

  select greatest(0, coalesce(ss.booking_buffer_minutes, 0))
    into v_buffer
  from public.site_settings ss
  order by ss.id
  limit 1;
  v_buffer := coalesce(v_buffer, 0);

  if p_status not in ('cancelled') and exists (
    select 1
    from public.bookings b
    where b.barber_id = p_barber_id
      and b.id <> p_booking_id
      and lower(coalesce(b.status, '')) not in ('cancelled','canceled')
      and b.start_at < p_start_at + make_interval(mins => v_duration + v_buffer)
      and b.start_at + make_interval(mins => greatest(10, coalesce(b.service_duration_minutes, 60)) + v_buffer) > p_start_at
  ) then
    raise exception 'Jadwal barber tersebut sudah terisi. Pilih tanggal atau jam lain.';
  end if;

  update public.bookings
  set customer_name = trim(p_customer_name),
      phone = trim(p_phone),
      address = trim(p_address),
      barber_id = p_barber_id,
      start_at = p_start_at,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      status = p_status
  where id = p_booking_id;

  return true;
end;
$rnc$;

revoke all on function public.rnc_admin_update_booking(uuid,text,text,text,uuid,timestamptz,text,text) from public;
grant execute on function public.rnc_admin_update_booking(uuid,text,text,text,uuid,timestamptz,text,text) to authenticated;
