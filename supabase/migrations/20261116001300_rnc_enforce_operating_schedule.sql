-- Enforce the public operating schedule inside the booking transaction.
-- Local operating time is Asia/Jakarta (WIB), matching the service area.
create or replace function public.customer_create_booking(
  p_customer_name text,
  p_phone text,
  p_address text,
  p_barber_id uuid,
  p_start_at timestamptz,
  p_notes text,
  p_booking_code text,
  p_duration_minutes integer default 60,
  p_service_id uuid default null,
  p_service_name text default 'Personal Barber',
  p_customer_latitude double precision default null,
  p_customer_longitude double precision default null
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
  v_service_name text;
  v_horizon_days integer := 14;
  v_schedule jsonb := '{}'::jsonb;
  v_local_start timestamp;
  v_local_date text;
  v_local_time text;
  v_open_text text;
  v_close_text text;
  v_open_time time;
  v_close_time time;
  v_slot_interval integer := 60;
  v_day_of_week integer;
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
     or p_booking_code is null
     or p_booking_code !~ '^[0-9]{5}$'
     or length(coalesce(p_notes, '')) > 1000
     or ((p_customer_latitude is null) <> (p_customer_longitude is null))
     or (p_customer_latitude is not null and p_customer_latitude not between -90 and 90)
     or (p_customer_longitude is not null and p_customer_longitude not between -180 and 180) then
    raise exception 'Data booking tidak valid.';
  end if;

  if p_service_id is null then
    raise exception 'Pilih layanan yang tersedia sebelum membuat booking.';
  end if;

  select s.duration_minutes, s.name
    into v_duration, v_service_name
  from public.services s
  where s.id = p_service_id and s.is_active = true;

  if not found then
    raise exception 'Layanan tidak tersedia. Silakan pilih layanan lain.';
  end if;

  if v_duration not between 10 and 480 or length(v_service_name) > 120 then
    raise exception 'Durasi atau nama layanan tidak valid.';
  end if;

  select greatest(1, least(30, coalesce(ss.booking_horizon_days, 14))),
         coalesce(ss.schedule_config, '{}'::jsonb)
    into v_horizon_days, v_schedule
  from public.site_settings ss
  where ss.id = 1;

  v_horizon_days := coalesce(v_horizon_days, 14);
  v_schedule := coalesce(v_schedule, '{}'::jsonb);

  if p_start_at > now() + make_interval(days => v_horizon_days) then
    raise exception 'Booking hanya dapat dibuat maksimal % hari ke depan.', v_horizon_days;
  end if;

  v_open_text := coalesce(nullif(v_schedule->>'open_time',''), '08:00');
  v_close_text := coalesce(nullif(v_schedule->>'close_time',''), '21:00');
  if v_open_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or v_close_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'Pengaturan jam operasional tidak valid. Hubungi admin.';
  end if;
  v_open_time := v_open_text::time;
  v_close_time := v_close_text::time;
  if v_close_time <= v_open_time then
    raise exception 'Jam tutup harus lebih besar dari jam buka.';
  end if;

  if coalesce(v_schedule->>'slot_interval','') ~ '^(30|60|90|120)$' then
    v_slot_interval := (v_schedule->>'slot_interval')::integer;
  end if;

  v_local_start := p_start_at at time zone 'Asia/Jakarta';
  v_local_date := to_char(v_local_start, 'YYYY-MM-DD');
  v_local_time := to_char(v_local_start, 'HH24:MI');
  v_day_of_week := extract(dow from v_local_start)::integer;

  if v_local_start::date in (
    select value::date
    from jsonb_array_elements_text(
      case when jsonb_typeof(v_schedule->'blocked_dates') = 'array'
        then v_schedule->'blocked_dates' else '[]'::jsonb end
    ) as dates(value)
    where value ~ '^\\d{4}-\\d{2}-\\d{2}$'
  ) then
    raise exception 'Tanggal tersebut tidak menerima booking.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(v_schedule->'weekly_days_off') = 'array'
        then v_schedule->'weekly_days_off' else '[]'::jsonb end
    ) as days(value)
    where value ~ '^[0-6]$' and value::integer = v_day_of_week
  ) then
    raise exception 'Hari tersebut merupakan hari libur.';
  end if;

  if (v_local_start::time < v_open_time)
     or (v_local_start + make_interval(mins => v_duration) > v_local_start::date + v_close_time) then
    raise exception 'Waktu booking harus berada dalam jam operasional.';
  end if;

  if mod(
    (extract(hour from v_local_start)::integer * 60 + extract(minute from v_local_start)::integer)
      - (extract(hour from v_open_time)::integer * 60 + extract(minute from v_open_time)::integer),
    v_slot_interval
  ) <> 0 then
    raise exception 'Pilih jam sesuai interval booking yang tersedia.';
  end if;

  if (v_local_date || '|' || v_local_time) in (
    select value
    from jsonb_array_elements_text(
      case when jsonb_typeof(v_schedule->'blocked_times') = 'array'
        then v_schedule->'blocked_times' else '[]'::jsonb end
    ) as times(value)
  ) then
    raise exception 'Jam tersebut sedang diblokir admin.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_barber_id::text, 0));

  if not exists (
    select 1 from public.barbers b
    where b.id = p_barber_id and coalesce(b.is_active,true) = true
  ) then
    raise exception 'Barber tidak ditemukan atau sedang tidak aktif.';
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
    status, booking_code, service_id, service_name, service_duration_minutes,
    customer_latitude, customer_longitude
  ) values (
    trim(p_customer_name), trim(p_phone), trim(p_address), p_barber_id,
    p_start_at, nullif(trim(coalesce(p_notes, '')), ''), 'pending',
    p_booking_code, p_service_id, v_service_name, v_duration,
    p_customer_latitude, p_customer_longitude
  )
  returning id into v_booking_id;

  return v_booking_id;
end;
$rnc$;

revoke all on function public.customer_create_booking(text,text,text,uuid,timestamptz,text,text,integer,uuid,text,double precision,double precision) from public;
grant execute on function public.customer_create_booking(text,text,text,uuid,timestamptz,text,text,integer,uuid,text,double precision,double precision) to anon, authenticated;
