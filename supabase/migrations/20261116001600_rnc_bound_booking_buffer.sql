-- Keep the owner-configurable travel/preparation buffer within a practical range.
-- Existing rows are retained; out-of-range legacy values are normalized before validation.
update public.site_settings
set booking_buffer_minutes = greatest(0, least(180, coalesce(booking_buffer_minutes, 0)))
where booking_buffer_minutes < 0 or booking_buffer_minutes > 180 or booking_buffer_minutes is null;

do $rnc$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.site_settings'::regclass
      and conname = 'rnc_booking_buffer_minutes_range'
  ) then
    alter table public.site_settings
      add constraint rnc_booking_buffer_minutes_range
      check (booking_buffer_minutes between 0 and 180);
  end if;
end;
$rnc$;

comment on column public.site_settings.booking_buffer_minutes is
  'Owner-configurable gap between barber appointments, in minutes (0–180). Enforced by atomic booking and reschedule RPCs.';
