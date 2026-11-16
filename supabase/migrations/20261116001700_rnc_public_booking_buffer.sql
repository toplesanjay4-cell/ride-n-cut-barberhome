-- The appointment buffer is operationally safe to expose to the public booking UI.
-- It contains no owner identity, financial data, or home-service origin details.
grant select (booking_buffer_minutes) on table public.site_settings to anon;
comment on column public.site_settings.booking_buffer_minutes is
  'Publicly readable booking gap (minutes) so customer slot availability matches database conflict validation; owner-controlled, 0–180.';
