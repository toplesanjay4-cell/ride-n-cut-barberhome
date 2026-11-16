-- Keep raw booking rows private. The customer page receives only occupied
-- intervals through a narrow SECURITY DEFINER RPC; active admins retain read-only
-- table access under an explicit owner/staff RLS guard.
alter table public.bookings enable row level security;

revoke all privileges on table public.bookings from public, anon, authenticated;
grant select on table public.bookings to authenticated;

drop policy if exists "rnc active admins read bookings" on public.bookings;
create policy "rnc active admins read bookings"
on public.bookings
for select
to authenticated
using (public.rnc_has_role(array['owner','staff']));

-- A restrictive policy prevents any older permissive SELECT policy from
-- widening access to inactive or unassigned authenticated accounts.
drop policy if exists "rnc active admins restrict booking reads" on public.bookings;
create policy "rnc active admins restrict booking reads"
on public.bookings
as restrictive
for select
to authenticated
using (public.rnc_has_role(array['owner','staff']));

-- Customers need availability, not customer names, phone numbers, or addresses.
create or replace function public.customer_booking_slots(
  p_barber_id uuid,
  p_date date
)
returns table (
  start_at timestamptz,
  service_duration_minutes integer
)
language sql
stable
security definer
set search_path = public
as $rnc$
  select
    b.start_at,
    greatest(10, least(480, coalesce(b.service_duration_minutes, 60)))
  from public.bookings b
  where p_barber_id is not null
    and p_date is not null
    and b.barber_id = p_barber_id
    and b.start_at >= ((p_date::timestamp - interval '12 hours') at time zone 'Asia/Jakarta')
    and b.start_at <= ((p_date::timestamp + interval '23 hours 59 minutes 59.999 seconds') at time zone 'Asia/Jakarta')
    and lower(coalesce(b.status, '')) not in ('cancelled', 'canceled')
  order by b.start_at;
$rnc$;

revoke all on function public.customer_booking_slots(uuid,date) from public;
grant execute on function public.customer_booking_slots(uuid,date) to anon, authenticated;

comment on function public.customer_booking_slots(uuid,date) is
  'Returns only occupied start times and service durations for a barber and local date; customer identity and address fields are never exposed.';
