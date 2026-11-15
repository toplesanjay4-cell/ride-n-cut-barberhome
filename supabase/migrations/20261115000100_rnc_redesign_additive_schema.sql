-- Ride N Cut: additive schema for the redesigned booking and operations system.
-- Safe by design: this migration does not delete, rename, or rewrite existing rows.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','staff')),
  display_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.rnc_has_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
      and is_active = true
      and role = any(required_roles)
  );
$;

-- Limit helper execution to app roles; anon receives only a boolean role check.
revoke all on function public.rnc_has_role(text[]) from public;
grant execute on function public.rnc_has_role(text[]) to anon, authenticated;

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  duration_minutes integer not null default 60 check (duration_minutes between 10 and 480),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  method_type text not null check (method_type in ('cash','bank_transfer','e_wallet','qris')),
  provider_name text not null,
  account_name text,
  account_number text,
  instructions text,
  qr_image_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.booking_price_quotes (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  service_name text not null,
  service_price numeric(12,2) not null default 0 check (service_price >= 0),
  travel_fee numeric(12,2) not null default 0 check (travel_fee >= 0),
  total_price numeric(12,2) generated always as (service_price + travel_fee) stored,
  quoted_by uuid references auth.users(id) on delete set null,
  quoted_at timestamptz not null default now(),
  customer_approved_at timestamptz,
  approval_channel text check (approval_channel in ('website','whatsapp')),
  notes text
);

create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 0),
  method_type text not null check (method_type in ('cash','bank_transfer','e_wallet','qris')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','waiting_verification','paid','rejected','refunded')),
  proof_url text,
  received_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_custom boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.expense_categories(id) on delete set null,
  description text not null,
  amount numeric(12,2) not null check (amount >= 0),
  expense_date date not null default current_date,
  created_by uuid references auth.users(id) on delete set null,
  is_automatic boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- New fields are nullable/defaulted so existing bookings remain valid and readable.
alter table public.bookings
  add column if not exists service_id uuid references public.services(id) on delete set null,
  add column if not exists service_name text,
  add column if not exists service_duration_minutes integer,
  add column if not exists quoted_service_price numeric(12,2),
  add column if not exists travel_fee numeric(12,2),
  add column if not exists total_price numeric(12,2),
  add column if not exists price_approved_at timestamptz,
  add column if not exists price_approval_channel text,
  add column if not exists payment_status text not null default 'unpaid',
  add column if not exists payment_method text,
  add column if not exists payment_proof_url text,
  add column if not exists customer_latitude double precision,
  add column if not exists customer_longitude double precision,
  add column if not exists cancellation_requested_at timestamptz,
  add column if not exists cancellation_reviewed_at timestamptz;

alter table public.site_settings
  add column if not exists origin_latitude double precision,
  add column if not exists origin_longitude double precision,
  add column if not exists booking_horizon_days integer not null default 14,
  add column if not exists booking_buffer_minutes integer not null default 0,
  add column if not exists automatic_expense_rules jsonb not null default '[]'::jsonb;

insert into public.expense_categories(name, is_custom)
values
 ('Transport', false), ('Equipment', false), ('Supplies', false),
 ('Operational', false), ('Other', false)
on conflict (name) do nothing;

alter table public.user_roles enable row level security;
alter table public.services enable row level security;
alter table public.payment_methods enable row level security;
alter table public.booking_price_quotes enable row level security;
alter table public.booking_payments enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;

-- Users can read their own role. Owner provisioning is intentionally manual
-- for the first owner account; see docs/SETUP-REDESIGN.md.
create policy "rnc users read own role" on public.user_roles
  for select to authenticated using (user_id = auth.uid() or public.rnc_has_role(array['owner']));

create policy "rnc owner manages roles" on public.user_roles
  for all to authenticated
  using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create policy "rnc public reads active services" on public.services
  for select to anon, authenticated using (is_active = true or public.rnc_has_role(array['owner','staff']));
create policy "rnc owner manages services" on public.services
  for all to authenticated using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create policy "rnc public reads active payment methods" on public.payment_methods
  for select to anon, authenticated using (is_active = true or public.rnc_has_role(array['owner','staff']));
create policy "rnc owner manages payment methods" on public.payment_methods
  for all to authenticated using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create policy "rnc staff reads quotes" on public.booking_price_quotes
  for select to authenticated using (public.rnc_has_role(array['owner','staff']));
create policy "rnc staff creates quotes" on public.booking_price_quotes
  for insert to authenticated with check (public.rnc_has_role(array['owner','staff']));
create policy "rnc staff updates quotes" on public.booking_price_quotes
  for update to authenticated using (public.rnc_has_role(array['owner','staff']))
  with check (public.rnc_has_role(array['owner','staff']));

create policy "rnc staff reads payments" on public.booking_payments
  for select to authenticated using (public.rnc_has_role(array['owner','staff']));
create policy "rnc staff records payments" on public.booking_payments
  for insert to authenticated with check (public.rnc_has_role(array['owner','staff']));
create policy "rnc staff updates payments" on public.booking_payments
  for update to authenticated using (public.rnc_has_role(array['owner','staff']))
  with check (public.rnc_has_role(array['owner','staff']));

create policy "rnc staff reads expense categories" on public.expense_categories
  for select to authenticated using (public.rnc_has_role(array['owner','staff']));
create policy "rnc owner manages expense categories" on public.expense_categories
  for all to authenticated using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create policy "rnc owner manages expenses" on public.expenses
  for all to authenticated using (public.rnc_has_role(array['owner']))
  with check (public.rnc_has_role(array['owner']));

create index if not exists booking_price_quotes_booking_id_idx on public.booking_price_quotes(booking_id, quoted_at desc);
create index if not exists booking_payments_booking_id_idx on public.booking_payments(booking_id, created_at desc);
create index if not exists expenses_expense_date_idx on public.expenses(expense_date desc);
create index if not exists bookings_service_id_idx on public.bookings(service_id);
