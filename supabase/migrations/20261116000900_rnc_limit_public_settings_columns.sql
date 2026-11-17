-- Keep private owner configuration (including the home-service origin pin
-- and automatic expense rules) out of the anonymous customer API.
-- Authenticated owner/staff access is preserved; the customer page explicitly
-- selects only the public presentation and schedule fields.
revoke select on table public.site_settings from anon, public;

-- Preserve full settings access for authenticated owner/staff sessions.
grant select on table public.site_settings to authenticated;

grant select (
  id,
  brand_name,
  hero_title,
  hero_subtitle,
  accent_color,
  services,
  schedule_config
) on table public.site_settings to anon;

comment on table public.site_settings is
  'Anonymous clients may read only public presentation and schedule columns; private owner settings remain authenticated-only.';
